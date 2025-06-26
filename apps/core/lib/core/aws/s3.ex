defmodule Core.AWS.S3 do
  @moduledoc """
  Helper module for AWS S3 operations.
  """

  alias ExAws.S3
  require Logger

  @doc false
  def validate_config! do
    bucket = get_bucket()
    region = Application.get_env(:ex_aws, :region)
    access_key = Application.get_env(:ex_aws, :access_key_id)
    secret_key = Application.get_env(:ex_aws, :secret_access_key)

    cond do
      is_nil(bucket) or bucket == "" ->
        raise "Bucket not configured. Please set BUCKET_NAME environment variable."

      is_nil(access_key) or access_key == "" ->
        raise "Access key not configured. Please set AWS_ACCESS_KEY_ID environment variable."

      is_nil(secret_key) or secret_key == "" ->
        raise "Secret key not configured. Please set AWS_SECRET_ACCESS_KEY environment variable."

      is_nil(region) or region == "" ->
        raise "Region not configured. Please set AWS_REGION environment variable."

      true ->
        :ok
    end
  end

  @doc """
  Uploads a file to S3 and returns the URL.

  ## Parameters
    * `file_data` - The file data map from LiveView upload
    * `type` - The type of file (e.g., :avatar, :logo)
    * `opts` - Additional options like filename or path

  ## Returns
    * `{:ok, url}` - On successful upload
    * `{:error, reason}` - On failure
  """
  def upload_file(%{path: path, filename: filename}, type, opts \\ []) do
    case validate_config!() do
      :ok -> upload_validated_file(path, filename, type, opts)
      _error -> {:error, "Invalid AWS S3 configuration"}
    end
  end

  defp upload_validated_file(path, filename, type, opts) do
    bucket = get_bucket()
    content_type = Keyword.get(opts, :content_type) || get_content_type(filename)
    unique_filename = generate_unique_filename(filename)
    s3_path = build_s3_path(type, unique_filename)

    with {:ok, file_binary} <- File.read(path),
         {:ok, _response} <- do_upload(bucket, s3_path, file_binary, content_type) do
      url = get_file_url(bucket, s3_path)
      {:ok, url}
    else
      {:error, %File.Error{reason: reason}} ->
        {:error, "Could not read file: #{inspect(reason)}"}

      {:error, reason} ->
        {:error, "Upload failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Upload failed due to unexpected error: #{inspect(e)}"}
  end

  @doc """
  Uploads a new file to S3 and deletes the old file if it exists.

  ## Parameters
    * `file_data` - The file data map from LiveView upload
    * `type` - The type of file (e.g., :avatar, :logo)
    * `old_url` - URL of the old file to delete (optional)
    * `opts` - Additional options like filename or path

  ## Returns
    * `{:ok, url}` - On successful upload
    * `{:error, reason}` - On failure
  """
  def replace_file(%{path: path, filename: filename}, type, old_url \\ nil, opts \\ []) do
    # Don't delete default images or non-S3 URLs
    should_delete_old =
      old_url &&
        !is_default_image?(old_url) &&
        is_s3_url?(old_url)

    # First upload the new file
    case upload_file(%{path: path, filename: filename}, type, opts) do
      {:ok, new_url} ->
        # If old_url should be deleted, attempt to delete it
        if should_delete_old do
          # Log deletion attempt
          Logger.info("Deleting old file: #{old_url}")

          # Perform deletion in a separate task to avoid blocking
          Task.start(fn ->
            case delete_file(old_url) do
              :ok ->
                Logger.info("Successfully deleted old file: #{old_url}")

              {:error, reason} ->
                Logger.warning("Failed to delete old file: #{old_url}. Reason: #{reason}")
            end
          end)
        end

        # Return success regardless of whether old file deletion succeeded
        {:ok, new_url}

      # Return any upload errors
      error ->
        error
    end
  rescue
    e ->
      Logger.error("Error in replace_file: #{inspect(e)}")
      {:error, "Unexpected error during file replacement"}
  end

  @doc """
  Deletes a file from S3.

  ## Parameters
    * `url` - The URL of the file to delete

  ## Returns
    * `:ok` - On successful deletion
    * `{:error, reason}` - On failure
  """
  def delete_file(url) do
    # Skip deletion for default or non-S3 URLs
    if is_s3_url?(url) do
      bucket = get_bucket()
      path = extract_path_from_url(url)

      bucket
      |> S3.delete_object(path)
      |> ExAws.request()
      |> case do
        {:ok, _response} -> :ok
        {:error, error} -> {:error, "S3 deletion failed: #{inspect(error)}"}
      end
    else
      # For non-S3 URLs, just return ok
      :ok
    end
  end

  @doc """
  Checks if the given URL is an S3 URL for our configured bucket.

  ## Parameters
    * `url` - The URL to check

  ## Returns
    * `true` - If it's an S3 URL for our bucket
    * `false` - Otherwise
  """
  def is_s3_url?(url) when is_binary(url) do
    bucket = get_bucket()
    region = Application.get_env(:ex_aws, :region, "us-east-1")

    cond do
      # Check for standard S3 URL format
      String.contains?(url, "#{bucket}.s3.#{region}.amazonaws.com") -> true
      # Check for path-style S3 URL format
      String.contains?(url, "s3.#{region}.amazonaws.com/#{bucket}/") -> true
      # Check for CloudFront or custom domain URLs (if configured)
      String.contains?(url, "/uploads/") && String.contains?(url, ["avatar/", "logo/"]) -> true
      # Not an S3 URL or it's from a different bucket
      true -> false
    end
  end

  def is_s3_url?(nil), do: false
  def is_s3_url?(_), do: false

  @doc """
  Returns a presigned URL for an object, which allows temporary access to it.

  ## Parameters
    * `path` - The S3 path of the file
    * `expires_in` - How long the URL is valid for (in seconds), defaults to 3600 (1 hour)

  ## Returns
    * `{:ok, url}` - The presigned URL
    * `{:error, reason}` - On failure
  """
  def presigned_url(path, expires_in \\ 3600) do
    bucket = get_bucket()
    bucket |> S3.presigned_url(:get, path, expires_in: expires_in)
  end

  @doc """
  Checks if the given URL is a default/system image that should not be deleted.

  ## Parameters
    * `url` - The URL to check

  ## Returns
    * `true` - If it's a default/system image
    * `false` - Otherwise
  """
  def is_default_image?(url) when is_binary(url) do
    cond do
      # Empty URL
      url == "" -> true
      # Default avatar patterns
      String.contains?(url, "default-avatar") -> true
      String.contains?(url, "robohash.org") -> true
      String.contains?(url, "dicebear.com") -> true
      String.contains?(url, "ui-avatars.com") -> true
      String.contains?(url, "gravatar.com") -> true
      # Default logo patterns
      String.contains?(url, "default-logo") -> true
      String.contains?(url, "placeholder.com") -> true
      # Not a default image
      true -> false
    end
  end

  def is_default_image?(nil), do: true
  # Consider anything non-string as default for safety
  def is_default_image?(_), do: true

  # Private helpers

  defp get_bucket do
    Application.get_env(:ex_aws, :bucket)
  end

  defp get_content_type(filename) do
    case Path.extname(filename) do
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".svg" -> "image/svg+xml"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end

  defp generate_unique_filename(filename) do
    extension = Path.extname(filename)
    base_name = Path.basename(filename, extension)
    timestamp = :os.system_time(:millisecond)
    random_string = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    "#{base_name}-#{timestamp}-#{random_string}#{extension}"
  end

  defp build_s3_path(type, filename) do
    "uploads/#{type}/#{filename}"
  end

  defp get_file_url(bucket, path) do
    region = Application.get_env(:ex_aws, :region, "us-east-2")
    "https://#{bucket}.s3.#{region}.amazonaws.com/#{path}"
  end

  defp extract_path_from_url(url) do
    uri = URI.parse(url)
    path = uri.path

    # Handle both path styles (bucket.s3 and s3/bucket)
    path =
      case path do
        "/" <> rest -> rest
        path -> path
      end

    # If we're using virtual host style URLs, the bucket name won't be in the path
    bucket = get_bucket()

    if String.starts_with?(path, "#{bucket}/") do
      String.replace_prefix(path, "#{bucket}/", "")
    else
      path
    end
  end

  defp do_upload(bucket, s3_path, file_binary, content_type) do
    operation =
      S3.put_object(bucket, s3_path, file_binary, [
        {:content_type, content_type}
      ])

    ExAws.request(operation)
  end
end
