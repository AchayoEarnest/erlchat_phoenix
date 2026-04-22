defmodule Chat.Files do
  @moduledoc """
  File upload context.
  Supports local filesystem storage and AWS S3 (switchable via config).
  """

  alias Chat.{Repo, Files.Upload}

  @max_size   52_428_800  # 50 MB
  @allowed_types ~w(
    image/jpeg image/png image/gif image/webp
    application/pdf
    application/msword
    application/vnd.openxmlformats-officedocument.wordprocessingml.document
    text/plain
  )

  @doc "Validate, store, and persist metadata for an uploaded file."
  def save(%Plug.Upload{} = upload, user_id, room_id \\ nil) do
    with :ok             <- validate(upload),
         {:ok, key, url} <- store(upload) do
      %Upload{}
      |> Upload.changeset(%{
        uploader_id:  user_id,
        room_id:      room_id,
        filename:     key,
        original_name: upload.filename,
        file_type:    upload.content_type,
        file_size:    file_size(upload.path),
        storage_key:  key,
        url:          url
      })
      |> Repo.insert()
    end
  end

  @doc "Get file metadata by ID."
  def get(id), do: Repo.get(Upload, id)
  def get!(id), do: Repo.get!(Upload, id)

  @doc "Delete a file (checks ownership)."
  def delete(id, user_id) do
    case get(id) do
      nil   -> {:error, :not_found}
      %Upload{uploader_id: ^user_id} = upload ->
        delete_from_storage(upload.storage_key)
        Repo.delete(upload)
      _ ->
        {:error, :unauthorized}
    end
  end

  # ── Private ───────────────────────────────────────────────────

  defp validate(%Plug.Upload{content_type: ct, path: path}) do
    size = file_size(path)

    cond do
      size > @max_size        -> {:error, "File exceeds 50MB limit"}
      ct not in @allowed_types -> {:error, "Unsupported file type: #{ct}"}
      true                    -> :ok
    end
  end

  defp store(%Plug.Upload{filename: filename, path: tmp_path} = upload) do
    ext = Path.extname(filename)
    key = "#{Ecto.UUID.generate()}#{ext}"

    storage_type = Application.get_env(:chat, :storage, []) |> Keyword.get(:type, "local")

    case storage_type do
      "s3"   -> store_s3(tmp_path, key, upload.content_type)
      _local -> store_local(tmp_path, key)
    end
  end

  defp store_local(tmp_path, key) do
    storage = Application.get_env(:chat, :storage, [])
    base    = Keyword.get(storage, :local_path, "priv/uploads")
    dest    = Path.join(base, key)

    File.mkdir_p!(base)
    File.cp!(tmp_path, dest)

    base_url = Keyword.get(storage, :base_url, "http://localhost:8080")
    url = "#{base_url}/uploads/#{key}"
    {:ok, key, url}
  end

  defp store_s3(tmp_path, key, content_type) do
    bucket  = Application.get_env(:chat, :s3_bucket, "erlchat-uploads")
    content = File.read!(tmp_path)

    bucket
    |> ExAws.S3.put_object(key, content, content_type: content_type, acl: :public_read)
    |> ExAws.request()
    |> case do
      {:ok, _} ->
        region  = Application.get_env(:ex_aws, :region, "us-east-1")
        url     = "https://#{bucket}.s3.#{region}.amazonaws.com/#{key}"
        {:ok, key, url}
      {:error, reason} ->
        {:error, "S3 upload failed: #{inspect(reason)}"}
    end
  end

  defp delete_from_storage(key) do
    storage_type = Application.get_env(:chat, :storage, []) |> Keyword.get(:type, "local")
    case storage_type do
      "s3" ->
        bucket = Application.get_env(:chat, :s3_bucket)
        ExAws.S3.delete_object(bucket, key) |> ExAws.request()
      _ ->
        base = Application.get_env(:chat, :storage, []) |> Keyword.get(:local_path, "priv/uploads")
        File.rm(Path.join(base, key))
    end
  end

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end
end
