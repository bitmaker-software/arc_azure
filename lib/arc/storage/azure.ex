defmodule Arc.Storage.Azure do
  @moduledoc :false

  def put(definition, version, {file, scope}) do
    destination_dir = definition.storage_dir(version, {file, scope})

    options =
      definition.s3_object_headers(version, {file, scope})
      |> ensure_keyword_list()

    case upload_file(destination_dir, file, options) do
      {:ok, _conn} -> {:ok, file.file_name}
      {:error, conn} -> {:error, conn}
    end
  end

  def url(definition, version, file_and_scope, options \\ []) do
    temp_url_expires_after = Keyword.get(options, :temp_url_expires_after, default_tempurl_ttl())
    temp_url_filename = Keyword.get(options, :temp_url_filename, :false)
    temp_url_inline = Keyword.get(options, :temp_url_inline, :true)
    temp_url_method = Keyword.get(options, :temp_url_method, "GET")
    options =
    Keyword.delete(options, :signed)
    |> Keyword.merge([
      temp_url_expires_after: temp_url_expires_after,
      temp_url_filename: temp_url_filename,
      temp_url_inline: temp_url_inline,
      temp_url_method: temp_url_method
      ]
    )
    build_url(definition, version, file_and_scope, options)
  end

  def delete(_definition, _version, {file, :nil}) do
    server_object = parse_objectname_from_url(file.file_name)
    ExAzure.request!(:delete_blob, [container(), server_object])
    :ok
  end
  def delete(definition, version, {file, scope}) do
    server_object = build_path(definition, version, {file, scope})
    ExAzure.request!(:delete_blob, [container(), server_object])
    :ok
  end

  defp container() do
    Application.get_env(:arc_azure, :container)
  end

  def default_tempurl_ttl() do
    Application.get_env(:arc, :default_tempurl_ttl, (30 * 24 * 60 * 60))
  end

  defp host() do
    Application.get_env(:arc_azure, :cdn_url) <> "/" <> container()
  end

  defp build_path(definition, version, file_and_scope) do
    destination_dir = definition.storage_dir(version, file_and_scope)
    filename = Arc.Definition.Versioning.resolve_file_name(definition, version, file_and_scope)
    Path.join([destination_dir, filename])
  end

  defp build_url(definition, version, file_and_scope, _options) do
    Path.join(host(), build_path(definition, version, file_and_scope))
  end

  defp parse_objectname_from_url(url) do
    [_host, server_object] = String.split(url, "#{host()}/")
    server_object
  end

  defp upload_file(destination_dir, file, options \\ []) do
    filename = Path.join(destination_dir, file.file_name)
    ExAzure.request(:put_block_blob, [container(), filename, get_binary_file(file), options])
  end

  defp get_binary_file(%{path: nil} = file), do: file.binary
  defp get_binary_file(%{path: _} = file), do: File.read!(file.path)

  defp ensure_keyword_list(list) when is_list(list), do: list
  defp ensure_keyword_list(map) when is_map(map), do: Map.to_list(map)
end
