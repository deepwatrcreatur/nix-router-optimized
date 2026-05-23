#!/usr/bin/env elixir

Code.require_file("clat_control_plane_elixir.ex", __DIR__)

alias RouterClatElixir.{ControlPlane, MappingStore}

defmodule RouterClatElixir.Main do
  def run(argv) do
    opts = ControlPlane.parse_args(argv)
    {:ok, store_pid} = MappingStore.start_link(opts)

    spawn_link(fn -> gc_loop(store_pid, opts) end)
    spawn_link(fn -> status_file_loop(store_pid, opts) end)
    spawn_link(fn -> status_http_loop(store_pid, opts) end)

    sockets =
      Enum.map(opts.listen_addresses, fn listen_addr ->
        {:ok, ip} = :inet.parse_address(String.to_charlist(listen_addr))
        {:ok, socket} = :gen_udp.open(opts.port, [:binary, {:ip, ip}, active: false, reuseaddr: true])
        socket
      end)

    Enum.each(sockets, fn socket ->
      spawn_link(fn -> serve_dns(socket, store_pid, opts) end)
    end)

    Process.sleep(:infinity)
  end

  defp serve_dns(socket, store_pid, opts) do
    case :gen_udp.recv(socket, 0) do
      {:ok, {ip, port, data}} ->
        response = ControlPlane.handle_query(data, store_pid, opts)
        if response, do: :gen_udp.send(socket, ip, port, response)
        serve_dns(socket, store_pid, opts)

      {:error, _reason} ->
        :ok
    end
  end

  defp gc_loop(store_pid, opts) do
    Process.sleep(opts.gc_interval * 1000)
    MappingStore.run_gc(store_pid, opts)
    gc_loop(store_pid, opts)
  end

  defp status_file_loop(store_pid, opts) do
    MappingStore.render_status_file(store_pid, opts, true, "elixir-preview+tayga", backend_healthy?())
    Process.sleep(10_000)
    status_file_loop(store_pid, opts)
  end

  defp status_http_loop(store_pid, opts) do
    {:ok, listen_socket} =
      :gen_tcp.listen(opts.status_port, [:binary, packet: :raw, active: false, reuseaddr: true, ip: {127, 0, 0, 1}])

    accept_loop(listen_socket, store_pid, opts)
  end

  defp accept_loop(listen_socket, store_pid, opts) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, socket} ->
        spawn(fn -> handle_status_conn(socket, store_pid, opts) end)
        accept_loop(listen_socket, store_pid, opts)

      {:error, _reason} ->
        :ok
    end
  end

  defp handle_status_conn(socket, store_pid, opts) do
    _ = :gen_tcp.recv(socket, 0, 1000)

    body =
      MappingStore.current_status(store_pid, opts, true, "elixir-preview+tayga", backend_healthy?())
      |> :json.encode()

    response =
      "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n#{body}"

    :gen_tcp.send(socket, response)
    :gen_tcp.close(socket)
  end

  defp backend_healthy? do
    case System.cmd("systemctl", ["is-active", "router-clat-tayga.service"], stderr_to_stdout: true) do
      {"active\n", 0} -> true
      _ -> false
    end
  end
end

RouterClatElixir.Main.run(System.argv())
