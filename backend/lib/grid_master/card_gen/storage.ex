defmodule GridMaster.CardGen.Storage do
  @moduledoc """
  生成圖儲存。R2 環境變數齊備時走 S3 相容 API（Req 內建 SigV4），
  否則落到本地 priv/static/uploads（開發用；生產請務必設定 R2）。

  需要的環境變數：
    R2_ENDPOINT           https://<account_id>.r2.cloudflarestorage.com
    R2_BUCKET             bucket 名
    R2_ACCESS_KEY_ID / R2_SECRET_ACCESS_KEY
    R2_PUBLIC_BASE        對外讀取用的公開網域（R2 public bucket 或自訂網域）
  """

  require Logger

  @doc "存一張 PNG,回傳可公開讀取的 URL。"
  def put_image(binary) when is_binary(binary) do
    key = "card-art/#{Date.utc_today() |> Date.to_iso8601()}/#{unique_name()}.png"

    case r2_config() do
      nil -> put_local(key, binary)
      config -> put_r2(config, key, binary)
    end
  end

  defp unique_name do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp r2_config do
    env = &System.get_env/1

    with endpoint when is_binary(endpoint) <- env.("R2_ENDPOINT"),
         bucket when is_binary(bucket) <- env.("R2_BUCKET"),
         key_id when is_binary(key_id) <- env.("R2_ACCESS_KEY_ID"),
         secret when is_binary(secret) <- env.("R2_SECRET_ACCESS_KEY"),
         public when is_binary(public) <- env.("R2_PUBLIC_BASE") do
      %{endpoint: endpoint, bucket: bucket, key_id: key_id, secret: secret, public: public}
    else
      _missing -> nil
    end
  end

  defp put_r2(config, key, binary) do
    url = "#{config.endpoint}/#{config.bucket}/#{key}"

    request =
      Req.new(
        url: url,
        body: binary,
        headers: [{"content-type", "image/png"}],
        aws_sigv4: [
          access_key_id: config.key_id,
          secret_access_key: config.secret,
          service: :s3,
          region: "auto"
        ]
      )

    case Req.put(request) do
      {:ok, %{status: status}} when status in 200..299 ->
        {:ok, "#{String.trim_trailing(config.public, "/")}/#{key}"}

      {:ok, %{status: status, body: body}} ->
        {:error, "R2 HTTP #{status}: #{body |> inspect() |> String.slice(0, 300)}"}

      {:error, exception} ->
        {:error, "R2: " <> Exception.message(exception)}
    end
  end

  # 本地 fallback:寫 priv/static/uploads,由 Plug.Static 以 /uploads 服務
  defp put_local(key, binary) do
    name = String.replace(key, "/", "_")
    dir = Path.join(Application.app_dir(:grid_master, "priv/static"), "uploads")
    File.mkdir_p!(dir)

    case File.write(Path.join(dir, name), binary) do
      :ok ->
        Logger.info("card_gen: R2 未設定,圖存本地 uploads/#{name}")
        {:ok, "/uploads/" <> name}

      {:error, reason} ->
        {:error, "local write: #{reason}"}
    end
  end
end
