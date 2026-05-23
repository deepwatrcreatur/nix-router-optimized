defmodule RouterClatElixir.MappingStore do
  use Agent
  import Bitwise

  def start_link(opts) do
    Agent.start_link(fn -> init_state(opts) end)
  end

  def lookup_or_allocate(pid, opts, ipv6_addr, dns_name \\ nil) do
    {ipv4, persist_state} =
      Agent.get_and_update(pid, fn state ->
        now = now_secs()

        case Map.get(state.mappings, ipv6_addr) do
          %{"expiresAt" => expires_at} = existing when expires_at > now ->
            {updated, persist?} = refresh_mapping(existing, now, opts.mapping_ttl, dns_name)
            new_state = %{state | mappings: Map.put(state.mappings, ipv6_addr, updated)}
            {{updated["ipv4"], maybe_persist_snapshot(persist?, new_state)}, new_state}

          _ ->
            case next_free_v4(state) do
              nil ->
                {{nil, nil}, state}

              v4 ->
                mapping = %{
                  "version" => 1,
                  "ipv4" => v4,
                  "ipv6" => ipv6_addr,
                  "names" => if(dns_name, do: [dns_name], else: []),
                  "createdAt" => now,
                  "lastDnsAnswerAt" => now,
                  "lastFlowSeenAt" => nil,
                  "expiresAt" => now + opts.mapping_ttl,
                  "state" => "active"
                }

                new_state = %{
                  state
                  | mappings: Map.put(state.mappings, ipv6_addr, mapping),
                    allocated_v4: MapSet.put(state.allocated_v4, v4)
                }

                {{v4, new_state}, new_state}
            end
        end
      end)

    maybe_persist_state(persist_state, opts)
    ipv4
  end

  def run_gc(pid, opts) do
    {removed, persist_state} =
      Agent.get_and_update(pid, fn state ->
        now = now_secs()

        {remaining, expired} =
          Enum.split_with(state.mappings, fn {_ipv6, mapping} ->
            mapping["expiresAt"] > now
          end)

        removed = length(expired)

        if removed == 0 do
          {{0, nil}, state}
        else
          mappings = Map.new(remaining)

          allocated_v4 =
            mappings
            |> Map.values()
            |> Enum.map(& &1["ipv4"])
            |> MapSet.new()

          new_state = %{state | mappings: mappings, allocated_v4: allocated_v4}
          {{removed, new_state}, new_state}
        end
      end)

    maybe_persist_state(persist_state, opts)
    removed
  end

  def get_stats(pid) do
    Agent.get(pid, fn state ->
      now = now_secs()
      active = Enum.count(state.mappings, fn {_k, mapping} -> mapping["expiresAt"] > now end)

      %{
        "total" => map_size(state.mappings),
        "active" => active,
        "poolUsed" => MapSet.size(state.allocated_v4),
        "poolSize" => state.pool_size
      }
    end)
  end

  def mapping(pid, ipv6_addr), do: Agent.get(pid, fn state -> Map.get(state.mappings, ipv6_addr) end)
  def state(pid), do: Agent.get(pid, & &1)

  def render_status_file(pid, opts, dns_listening, backend_name, backend_healthy) do
    status = current_status(pid, opts, dns_listening, backend_name, backend_healthy) |> :json.encode()
    File.mkdir_p!(Path.dirname(opts.status_path))
    tmp = opts.status_path <> ".tmp"
    File.write!(tmp, status)
    File.rename!(tmp, opts.status_path)
  end

  def current_status(pid, opts, dns_listening, backend_name, backend_healthy) do
    stats = get_stats(pid)

    state =
      cond do
        !dns_listening -> "inactive"
        !backend_healthy -> "degraded"
        stats["active"] == 0 -> "active-idle"
        true -> "active-translating"
      end

    %{
      "version" => 1,
      "state" => state,
      "backend" => %{
        "name" => backend_name,
        "healthy" => backend_healthy
      },
      "dns" => %{
        "listening" => dns_listening,
        "listenPort" => opts.port
      },
      "mappings" => stats,
      "boundaries" => %{
        "ha" => false,
        "multiWan" => false,
        "note" => "Single-owner first-slice. No HA or failover guarantees."
      }
    }
  end

  def persist_state!(state, opts) do
    File.mkdir_p!(opts.state_dir)
    records = Map.values(state.mappings)

    state_body =
      %{
        "version" => 1,
        "savedAt" => now_secs(),
        "mappings" => records
      }
      |> :json.encode()

    File.write!(opts.state_file <> ".tmp", state_body)
    File.rename!(opts.state_file <> ".tmp", opts.state_file)

    artifact_body =
      %{
        "version" => 1,
        "generatedAt" => now_secs(),
        "mappingCount" => length(records),
        "mappings" =>
          Enum.map(records, fn mapping ->
            %{
              "ipv4" => mapping["ipv4"],
              "ipv6" => mapping["ipv6"],
              "expiresAt" => mapping["expiresAt"],
              "state" => mapping["state"]
            }
          end)
      }
      |> :json.encode()

    File.mkdir_p!(Path.dirname(opts.artifact_path))
    File.write!(opts.artifact_path <> ".tmp", artifact_body)
    File.rename!(opts.artifact_path <> ".tmp", opts.artifact_path)

    if opts.reload_cmd do
      System.cmd("/bin/sh", ["-lc", opts.reload_cmd])
    end
  end

  defp init_state(opts) do
    {pool_start, pool_end} = pool_range(opts.pool_cidr)

    base = %{
      pool_start: pool_start,
      pool_end: pool_end,
      pool_size: pool_end - pool_start + 1,
      mappings: %{},
      allocated_v4: MapSet.new()
    }

    if File.exists?(opts.state_file) do
      case File.read(opts.state_file) do
        {:ok, body} ->
          case :json.decode(body) do
            {:ok, %{"mappings" => mappings}} ->
              now = now_secs()

              active =
                Enum.filter(mappings, fn mapping ->
                  mapping["state"] == "active" and mapping["expiresAt"] > now
                end)

              %{
                base
                | mappings: Map.new(active, fn mapping -> {mapping["ipv6"], mapping} end),
                  allocated_v4: active |> Enum.map(& &1["ipv4"]) |> MapSet.new()
              }

            _ ->
              raise "State directory corrupt or unreadable: #{opts.state_file}"
          end

        _ ->
          raise "State directory corrupt or unreadable: #{opts.state_file}"
      end
    else
      base
    end
  end

  defp refresh_mapping(existing, now, mapping_ttl, dns_name) do
    updated =
      existing
      |> Map.put("lastDnsAnswerAt", now)
      |> Map.put("expiresAt", now + mapping_ttl)

    if is_nil(dns_name) or dns_name in (existing["names"] || []) do
      {updated, false}
    else
      {Map.put(updated, "names", (existing["names"] || []) ++ [dns_name]), true}
    end
  end

  defp maybe_persist_snapshot(true, state), do: state
  defp maybe_persist_snapshot(false, _state), do: nil

  defp maybe_persist_state(nil, _opts), do: :ok
  defp maybe_persist_state(state, opts), do: persist_state!(state, opts)

  defp next_free_v4(state) do
    Enum.find_value(state.pool_start..state.pool_end, fn int_ip ->
      v4 = int_to_ipv4(int_ip)
      if MapSet.member?(state.allocated_v4, v4), do: nil, else: v4
    end)
  end

  defp pool_range(cidr) do
    [address, prefix_len_str] = String.split(cidr, "/")
    prefix_len = String.to_integer(prefix_len_str)
    addr_int = ipv4_to_int(address)
    size = 1 <<< (32 - prefix_len)
    network = div(addr_int, size) * size
    first_host = if size > 2, do: network + 2, else: network + 1
    last_host = network + size - 2
    {first_host, last_host}
  end

  defp ipv4_to_int(address) do
    address
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
    |> Enum.reduce(0, fn octet, acc -> acc * 256 + octet end)
  end

  defp int_to_ipv4(int_ip) do
    [
      band(int_ip >>> 24, 255),
      band(int_ip >>> 16, 255),
      band(int_ip >>> 8, 255),
      band(int_ip, 255)
    ]
    |> Enum.map(&Integer.to_string/1)
    |> Enum.join(".")
  end

  defp now_secs, do: System.system_time(:millisecond) / 1000
end

defmodule RouterClatElixir.UpstreamSocketPool do
  use GenServer

  def start_link(upstreams, opts \\ []) do
    pool_size = Keyword.get(opts, :pool_size, max(2, System.schedulers_online()))
    GenServer.start_link(__MODULE__, {Enum.uniq(upstreams), pool_size})
  end

  def checkout(pid, upstream, timeout_ms \\ 6_000) do
    GenServer.call(pid, {:checkout, upstream}, timeout_ms)
  end

  def checkin(pid, upstream, socket) do
    GenServer.cast(pid, {:checkin, upstream, socket})
  end

  @impl true
  def init({upstreams, pool_size}) do
    available =
      Map.new(upstreams, fn upstream ->
        {upstream, Enum.map(1..pool_size, fn _ -> open_socket!() end)}
      end)

    {:ok, %{available: available, waiters: %{}}}
  end

  @impl true
  def handle_call({:checkout, upstream}, from, state) do
    case Map.get(state.available, upstream, []) do
      [socket | rest] ->
        {:reply, {:ok, socket}, put_in(state.available[upstream], rest)}

      [] ->
        waiters = Map.update(state.waiters, upstream, :queue.from_list([from]), &:queue.in(from, &1))
        {:noreply, %{state | waiters: waiters}}
    end
  end

  @impl true
  def handle_cast({:checkin, upstream, socket}, state) do
    queue = Map.get(state.waiters, upstream, :queue.new())

    case :queue.out(queue) do
      {{:value, from}, rest} ->
        GenServer.reply(from, {:ok, socket})
        {:noreply, %{state | waiters: Map.put(state.waiters, upstream, rest)}}

      {:empty, _queue} ->
        available = Map.update(state.available, upstream, [socket], &[socket | &1])
        {:noreply, %{state | available: available}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    state.available
    |> Map.values()
    |> List.flatten()
    |> Enum.each(&:gen_udp.close/1)
  end

  defp open_socket! do
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false])
    socket
  end
end

defmodule RouterClatElixir.Dns do
  import Bitwise

  @qtype_a 1
  @qtype_aaaa 28

  def qtype_a, do: @qtype_a
  def qtype_aaaa, do: @qtype_aaaa

  def extract_query_name(data) do
    case do_extract_query_name(data, 12, []) do
      {:ok, labels} -> labels |> Enum.reverse() |> Enum.join(".")
      :error -> nil
    end
  end

  defp do_extract_query_name(data, offset, labels) when offset < byte_size(data) do
    length = :binary.at(data, offset)

    cond do
      length == 0 ->
        {:ok, labels}

      length >= 192 ->
        :error

      offset + 1 + length > byte_size(data) ->
        :error

      true ->
        label = binary_part(data, offset + 1, length)
        do_extract_query_name(data, offset + 1 + length, [label | labels])
    end
  end

  defp do_extract_query_name(_data, _offset, _labels), do: :error

  def extract_query_type(data) do
    with {:ok, offset} <- skip_qname(data, 12),
         true <- offset + 2 <= byte_size(data) do
      <<_::binary-size(offset), qtype::16, _::binary>> = data
      qtype
    else
      _ -> nil
    end
  end

  def extract_query_name_bytes(data) do
    with {:ok, offset} <- skip_qname(data, 12) do
      binary_part(data, 12, offset - 12)
    else
      _ -> nil
    end
  end

  def rewrite_qtype(data, new_qtype) do
    with {:ok, offset} <- skip_qname(data, 12),
         true <- offset + 2 <= byte_size(data) do
      <<head::binary-size(offset), _old::16, tail::binary>> = data
      <<head::binary, new_qtype::16, tail::binary>>
    else
      _ -> nil
    end
  end

  def parse_response_records(data) when byte_size(data) < 12, do: {[], [], 0}

  def parse_response_records(data) do
    <<_id::16, flags::16, qdcount::16, ancount::16, _ns::16, _ar::16, _::binary>> = data
    rcode = band(flags, 0xF)

    case skip_questions(data, 12, qdcount) do
      {:ok, offset} -> parse_answers(data, offset, ancount, [], [], rcode)
      :error -> {[], [], rcode}
    end
  end

  def build_servfail(query_data) when byte_size(query_data) < 12, do: query_data

  def build_servfail(query_data) do
    <<qid::16, _::binary>> = query_data
    qdcount = qdcount(query_data)

    case skip_questions(query_data, 12, qdcount) do
      {:ok, offset} ->
        question = binary_part(query_data, 12, offset - 12)
        <<qid::16, 0x8182::16, qdcount::16, 0::16, 0::16, 0::16, question::binary>>

      :error ->
        query_data
    end
  end

  def build_dns_response(query_data, answers) do
    <<qid::16, _::binary>> = query_data
    qdcount = qdcount(query_data)

    case skip_questions(query_data, 12, qdcount) do
      {:ok, offset} ->
        question = binary_part(query_data, 12, offset - 12)
        header = <<qid::16, 0x8180::16, qdcount::16, length(answers)::16, 0::16, 0::16>>

        body =
          Enum.reduce(answers, <<>>, fn {name_bytes, rtype, rclass, ttl, rdata}, acc ->
            <<acc::binary, name_bytes::binary, rtype::16, rclass::16, ttl::32, byte_size(rdata)::16, rdata::binary>>
          end)

        <<header::binary, question::binary, body::binary>>

      :error ->
        build_servfail(query_data)
    end
  end

  def forward_query(data, {host, port}, timeout_ms \\ 5000, upstream_pool \\ nil) do
    if upstream_pool do
      with {:ok, socket} <- RouterClatElixir.UpstreamSocketPool.checkout(upstream_pool, {host, port}, timeout_ms) do
        try do
          do_forward_query(socket, data, host, port, timeout_ms)
        after
          RouterClatElixir.UpstreamSocketPool.checkin(upstream_pool, {host, port}, socket)
        end
      else
        _ -> nil
      end
    else
      {:ok, socket} = :gen_udp.open(0, [:binary, active: false])

      try do
        do_forward_query(socket, data, host, port, timeout_ms)
      after
        :gen_udp.close(socket)
      end
    end
  end

  defp resolve_host(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, addr} -> {:ok, addr}
      _ -> :inet.getaddr(String.to_charlist(host), :inet)
    end
  end

  defp parse_answers(_data, _offset, 0, a_records, aaaa_records, rcode),
    do: {Enum.reverse(a_records), Enum.reverse(aaaa_records), rcode}

  defp parse_answers(data, offset, remaining, a_records, aaaa_records, rcode) do
    case skip_name(data, offset) do
      {:ok, name_offset} ->
        if name_offset + 10 > byte_size(data) do
          {Enum.reverse(a_records), Enum.reverse(aaaa_records), rcode}
        else
          <<_::binary-size(name_offset), rtype::16, _rclass::16, ttl::32, rdlength::16, _::binary>> = data
          rdata_offset = name_offset + 10

          if rdata_offset + rdlength > byte_size(data) do
            {Enum.reverse(a_records), Enum.reverse(aaaa_records), rcode}
          else
            rdata = binary_part(data, rdata_offset, rdlength)
            next_offset = rdata_offset + rdlength

            cond do
              rtype == @qtype_a and rdlength == 4 ->
                <<a, b, c, d>> = rdata
                ip = Enum.join([a, b, c, d], ".")
                parse_answers(data, next_offset, remaining - 1, [{ip, ttl} | a_records], aaaa_records, rcode)

              rtype == @qtype_aaaa and rdlength == 16 ->
                <<a1::16, a2::16, a3::16, a4::16, a5::16, a6::16, a7::16, a8::16>> = rdata
                ip = :inet.ntoa({a1, a2, a3, a4, a5, a6, a7, a8}) |> to_string()
                parse_answers(data, next_offset, remaining - 1, a_records, [{ip, ttl} | aaaa_records], rcode)

              true ->
                parse_answers(data, next_offset, remaining - 1, a_records, aaaa_records, rcode)
            end
          end
        end

      :error ->
        {Enum.reverse(a_records), Enum.reverse(aaaa_records), rcode}
    end
  end

  defp qdcount(data) do
    <<_id::16, _flags::16, qdcount::16, _::binary>> = data
    qdcount
  end

  defp skip_questions(_data, offset, 0), do: {:ok, offset}

  defp skip_questions(data, offset, count) do
    with {:ok, next} <- skip_qname(data, offset),
         true <- next + 4 <= byte_size(data) do
      skip_questions(data, next + 4, count - 1)
    else
      _ -> :error
    end
  end

  defp skip_qname(data, offset) do
    cond do
      offset >= byte_size(data) ->
        :error

      true ->
        length = :binary.at(data, offset)

        cond do
          length == 0 -> {:ok, offset + 1}
          length >= 192 -> :error
          offset + 1 + length > byte_size(data) -> :error
          true -> skip_qname(data, offset + 1 + length)
        end
    end
  end

  defp skip_name(data, offset) do
    cond do
      offset >= byte_size(data) ->
        :error

      true ->
        length = :binary.at(data, offset)

        cond do
          length == 0 -> {:ok, offset + 1}
          length >= 192 -> if(offset + 2 <= byte_size(data), do: {:ok, offset + 2}, else: :error)
          offset + 1 + length > byte_size(data) -> :error
          true -> skip_name(data, offset + 1 + length)
        end
    end
  end

  defp do_forward_query(socket, data, host, port, timeout_ms) do
    with {:ok, host_addr} <- resolve_host(host),
         :ok <- :gen_udp.send(socket, host_addr, port, data),
         {:ok, {_ip, _port, response}} <- :gen_udp.recv(socket, 0, timeout_ms) do
      response
    else
      _ -> nil
    end
  end
end

defmodule RouterClatElixir.ControlPlane do
  alias RouterClatElixir.{Dns, MappingStore}

  def parse_args(argv) do
    {opts, _rest, _invalid} =
      OptionParser.parse(argv,
        strict: [
          pool: :string,
          mapping_ttl: :integer,
          gc_interval: :integer,
          state_dir: :string,
          artifact_path: :string,
          upstream: :keep,
          listen: :keep,
          port: :integer,
          prefer_synthesized: :boolean,
          reload_cmd: :string,
          status_port: :integer,
          status_path: :string
        ]
      )

    %{
      pool_cidr: Keyword.fetch!(opts, :pool),
      mapping_ttl: Keyword.get(opts, :mapping_ttl, 1800),
      gc_interval: Keyword.get(opts, :gc_interval, 60),
      state_dir: Keyword.fetch!(opts, :state_dir),
      state_file: Path.join(Keyword.fetch!(opts, :state_dir), "mappings.json"),
      artifact_path: Keyword.fetch!(opts, :artifact_path),
      upstreams:
        Keyword.get_values(opts, :upstream)
        |> Enum.map(fn upstream ->
          case String.split(upstream, ":", parts: 2) do
            [host, port] -> {host, String.to_integer(port)}
            [host] -> {host, 53}
          end
        end),
      listen_addresses: Keyword.get_values(opts, :listen),
      port: Keyword.get(opts, :port, 53),
      prefer_synthesized: Keyword.get(opts, :prefer_synthesized, false),
      reload_cmd: Keyword.get(opts, :reload_cmd),
      status_port: Keyword.get(opts, :status_port, 9467),
      status_path: Keyword.get(opts, :status_path, Path.join(Keyword.fetch!(opts, :state_dir), "status.json"))
    }
  end

  def handle_query(query_data, store_pid, opts) do
    qtype = Dns.extract_query_type(query_data)
    qname = Dns.extract_query_name(query_data)

    cond do
      is_nil(qtype) or is_nil(qname) ->
        Dns.build_servfail(query_data)

      qtype != Dns.qtype_a() ->
        forward_raw(query_data, opts) || Dns.build_servfail(query_data)

      true ->
        aaaa_query = Dns.rewrite_qtype(query_data, Dns.qtype_aaaa())

        a_task = Task.async(fn -> forward_raw(query_data, opts) end)

        aaaa_task =
          Task.async(fn ->
            if is_nil(aaaa_query), do: nil, else: forward_raw(aaaa_query, opts)
          end)

        a_response = Task.await(a_task, 6_000)

        if is_nil(a_response) do
          Dns.build_servfail(query_data)
        else
          {a_records, _ignored, a_rcode} = Dns.parse_response_records(a_response)
          aaaa_response = Task.await(aaaa_task, 6_000)
          {_a2, aaaa_records, _} = if aaaa_response, do: Dns.parse_response_records(aaaa_response), else: {[], [], 0}

          cond do
            a_rcode in [0, 3] and a_records == [] and aaaa_records == [] -> a_response
            a_records != [] and aaaa_records == [] -> a_response
            a_records != [] and aaaa_records != [] and !opts.prefer_synthesized -> a_response
            aaaa_records != [] -> synthesize_a(query_data, qname, aaaa_records, store_pid, opts)
            true -> a_response
          end
        end
    end
  end

  defp synthesize_a(query_data, qname, aaaa_records, store_pid, opts) do
    sorted_v6 = Enum.sort_by(aaaa_records, fn {ip, _ttl} -> ip end)

    chosen =
      Enum.find_value(sorted_v6, fn {ip6, ttl} ->
        case MappingStore.mapping(store_pid, ip6) do
          %{"expiresAt" => expires_at} ->
            if expires_at > now_secs(), do: {ip6, ttl}, else: nil
          _ -> nil
        end
      end) || List.first(sorted_v6)

    {target, target_ttl} = chosen
    v4 = MappingStore.lookup_or_allocate(store_pid, opts, target, qname)

    if is_nil(v4) do
      Dns.build_servfail(query_data)
    else
      expires_at = MappingStore.mapping(store_pid, target)["expiresAt"]
      remaining = expires_at - now_secs()
      synth_ttl = max(1, trunc(min(target_ttl, remaining)))
      name_bytes = Dns.extract_query_name_bytes(query_data)
      {:ok, ipv4_tuple} = :inet.parse_address(String.to_charlist(v4))
      rdata = :erlang.list_to_binary(Tuple.to_list(ipv4_tuple))
      Dns.build_dns_response(query_data, [{name_bytes, Dns.qtype_a(), 1, synth_ttl, rdata}])
    end
  end

  defp forward_raw(data, %{forward_fun: fun}), do: fun.(data)

  defp forward_raw(data, opts) do
    Enum.find_value(opts.upstreams, fn upstream ->
      Dns.forward_query(data, upstream, 5_000, Map.get(opts, :upstream_pool))
    end)
  end

  defp now_secs, do: System.system_time(:millisecond) / 1000
end
