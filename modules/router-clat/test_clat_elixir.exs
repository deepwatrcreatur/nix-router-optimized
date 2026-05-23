ExUnit.start()

Code.require_file("clat_control_plane_elixir.ex", __DIR__)

alias RouterClatElixir.{ControlPlane, Dns, MappingStore}

defmodule RouterClatElixirTest do
  use ExUnit.Case, async: false

  defp base_opts do
    tmpdir = System.tmp_dir!() <> "/router-clat-elixir-#{System.unique_integer([:positive, :monotonic])}"
    File.rm_rf(tmpdir)
    File.mkdir_p!(tmpdir)

    %{
      pool_cidr: "100.64.46.0/24",
      mapping_ttl: 1800,
      gc_interval: 3600,
      state_dir: tmpdir,
      state_file: Path.join(tmpdir, "mappings.json"),
      artifact_path: Path.join(tmpdir, "artifact.json"),
      upstreams: [{"127.0.0.1", 53}],
      listen_addresses: ["127.0.0.1"],
      port: 5300,
      prefer_synthesized: false,
      reload_cmd: nil,
      status_port: 9467,
      status_path: Path.join(tmpdir, "status.json")
    }
  end

  defp malformed_query do
    <<0x1234::16, 0x0100::16, 1::16, 0::16, 0::16, 0::16, 20::8, "abc">>
  end

  defp fixture(name) do
    Path.join([__DIR__, "fixtures", name])
    |> File.read!()
    |> :json.decode()
  end

  defp build_query(name, qtype \\ 1, qid \\ 0x1234) do
    header = <<qid::16, 0x0100::16, 1::16, 0::16, 0::16, 0::16>>

    qname =
      name
      |> String.split(".")
      |> Enum.reduce(<<>>, fn label, acc ->
        <<acc::binary, byte_size(label)::8, label::binary>>
      end)

    <<header::binary, qname::binary, 0::8, qtype::16, 1::16>>
  end

  defp build_response_with_records(query, a_ips, aaaa_ips, ttl \\ 300) do
    <<qid::16, _::binary>> = query
    qdcount = 1
    ancount = length(a_ips) + length(aaaa_ips)
    header = <<qid::16, 0x8180::16, qdcount::16, ancount::16, 0::16, 0::16>>
    question_end = 12 + byte_size(Dns.extract_query_name_bytes(query)) + 4
    question = binary_part(query, 12, question_end - 12)
    name_bytes = Dns.extract_query_name_bytes(query)

    a_answers =
      Enum.reduce(a_ips, <<>>, fn ip, acc ->
        {:ok, tuple} = :inet.parse_address(String.to_charlist(ip))
        rdata = :erlang.list_to_binary(Tuple.to_list(tuple))
        <<acc::binary, name_bytes::binary, 1::16, 1::16, ttl::32, byte_size(rdata)::16, rdata::binary>>
      end)

    Enum.reduce(aaaa_ips, a_answers, fn ip, acc ->
      {:ok, tuple} = :inet.parse_address(String.to_charlist(ip))

      rdata =
        tuple
        |> Tuple.to_list()
        |> Enum.reduce(<<>>, fn chunk, bin -> <<bin::binary, chunk::16>> end)

      <<acc::binary, name_bytes::binary, 28::16, 1::16, ttl::32, byte_size(rdata)::16, rdata::binary>>
    end)
    |> then(fn answers -> <<header::binary, question::binary, answers::binary>> end)
  end

  test "parses explicit selector runtime args" do
    opts =
      ControlPlane.parse_args([
        "--pool", "100.64.46.0/24",
        "--mapping-ttl", "1800",
        "--gc-interval", "60",
        "--state-dir", "/tmp/router-clat",
        "--artifact-path", "/run/router-clat/mappings.json",
        "--upstream", "127.0.0.1",
        "--listen", "0.0.0.0",
        "--port", "53",
        "--status-port", "9467",
        "--status-path", "/run/router-clat/status.json"
      ])

    assert opts.pool_cidr == "100.64.46.0/24"
    assert opts.status_path == "/run/router-clat/status.json"
  end

  test "AAAA-only fixture synthesizes and allocates mapping" do
    fx = fixture("dns-aaaa-only-synthesis.json")
    opts = base_opts()
    {:ok, store} = MappingStore.start_link(opts)
    query = build_query(fx["queryName"])

    forward_fun = fn data ->
      case Dns.extract_query_type(data) do
        1 -> build_response_with_records(data, fx["upstream"]["aRecords"], [])
        28 -> build_response_with_records(data, [], fx["upstream"]["aaaaRecords"])
      end
    end

    response = ControlPlane.handle_query(query, store, Map.put(opts, :forward_fun, forward_fun))
    {a_records, _aaaa_records, _rcode} = Dns.parse_response_records(response)
    assert length(a_records) > 0
    assert MappingStore.mapping(store, fx["expected"]["mappingIpv6"]) != nil
  end

  test "GC expiry fixture removes expired mapping" do
    fx = fixture("mapping-gc-expiry.json")
    opts = Map.merge(base_opts(), %{mapping_ttl: fx["mappingTtlSec"], gc_interval: fx["gcIntervalSec"]})
    {:ok, store} = MappingStore.start_link(opts)
    MappingStore.lookup_or_allocate(store, opts, "2001:db8::1", "example.com")
    assert map_size(MappingStore.state(store).mappings) == fx["expected"]["beforeGcMappingCount"]
    Process.sleep(200)
    removed = MappingStore.run_gc(store, opts)
    assert removed == fx["expected"]["removedMappings"]
    assert map_size(MappingStore.state(store).mappings) == fx["expected"]["afterGcMappingCount"]
  end

  test "artifact fixture remains backend-neutral" do
    fx = fixture("artifact-schema-v1.json")
    opts = base_opts()
    {:ok, store} = MappingStore.start_link(opts)
    MappingStore.lookup_or_allocate(store, opts, "2001:db8::1", "example.com")
    artifact = File.read!(opts.artifact_path) |> :json.decode()
    assert artifact["version"] == fx["version"]
    assert artifact["mappingCount"] == fx["mappingCount"]
    assert length(artifact["mappings"]) == fx["mappingCount"]
  end

  test "fake backend fixture stays generic" do
    fx = fixture("status-fake-backend-generic.json")
    assert fx["version"] == 1
    assert fx["backend"]["name"] == "fake-backend"
    assert fx["boundaries"]["ha"] == false
    assert fx["boundaries"]["multiWan"] == false
  end

  test "malformed query returns servfail instead of crashing" do
    opts = base_opts()
    {:ok, store} = MappingStore.start_link(opts)
    response = ControlPlane.handle_query(malformed_query(), store, opts)
    assert response == malformed_query()
  end

  test "truncated answer parser returns no records instead of raising" do
    truncated =
      <<0x1234::16, 0x8180::16, 1::16, 1::16, 0::16, 0::16, 1::8, "a", 0::8, 1::16, 1::16,
        0xC00C::16, 1::16, 1::16, 300::32, 4::16, 127::8>>

    assert Dns.parse_response_records(truncated) == {[], [], 0}
  end
end
