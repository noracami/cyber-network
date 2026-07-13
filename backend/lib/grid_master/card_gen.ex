defmodule GridMaster.CardGen do
  @moduledoc """
  卡面插圖生成（admin 工作台後端），一律走 OpenAI Batch API（半價）。

  流程：generate/2 上傳 JSONL、建 batch、寫入 pending 紀錄即回。之後由
  前端帶著 key 呼叫 check_pending/1 輪詢——API key 只活在單次請求的記憶體,
  後端不持有、不落地,所以輪詢的鑰匙由前端保管。
  """

  import Ecto.Query

  alias GridMaster.CardGen.{History, Storage}
  alias GridMaster.Repo

  @openai "https://api.openai.com/v1"
  @receive_timeout 120_000

  @doc "近期生成紀錄(新到舊)。"
  def list_history(limit \\ 50) do
    Repo.all(from h in History, order_by: [desc: h.inserted_at], limit: ^limit)
  end

  @doc """
  建立 batch 生成請求。成功回 `{:ok, history}`(status "pending"),
  建立失敗回 `{:error, history}`(status "failed"、帶 error_msg)。
  """
  def generate(api_key, %{prompt: prompt, model: model} = params) do
    size = Map.get(params, :size)
    n = params |> Map.get(:n, 1) |> min(8) |> max(1)
    base = %{prompt: prompt, model: model, size: size, n: n}

    with {:ok, file_id} <- upload_input(api_key, build_jsonl(prompt, model, size, n)),
         {:ok, batch_id} <- create_batch(api_key, file_id) do
      insert(:ok, Map.merge(base, %{status: "pending", batch_id: batch_id}))
    else
      {:error, reason} ->
        insert(:error, Map.merge(base, %{status: "failed", error_msg: reason}))
    end
  end

  @doc """
  輪詢所有 pending 紀錄的 batch 狀態並收割結果。回傳更新後的紀錄數。
  """
  def check_pending(api_key) do
    pending = Repo.all(from h in History, where: h.status == "pending")

    updated =
      Enum.count(pending, fn history ->
        case fetch_batch(api_key, history.batch_id) do
          {:ok, %{"status" => "completed"} = batch} -> finalize(api_key, history, batch)
          {:ok, %{"status" => status} = batch} when status in ~w(failed expired cancelled) ->
            fail(history, batch)

          _in_progress_or_error ->
            false
        end
      end)

    {:ok, updated}
  end

  # —— OpenAI Batch 三步:上傳 JSONL → 建 batch → 取結果 ——

  defp build_jsonl(prompt, model, size, n) do
    body =
      %{model: model, prompt: prompt, n: n}
      |> then(fn b -> if size in [nil, "", "auto"], do: b, else: Map.put(b, :size, size) end)

    Jason.encode!(%{
      custom_id: "card-art",
      method: "POST",
      url: "/v1/images/generations",
      body: body
    }) <> "\n"
  end

  defp upload_input(api_key, jsonl) do
    request =
      Req.new(
        url: @openai <> "/files",
        auth: {:bearer, api_key},
        receive_timeout: @receive_timeout,
        form_multipart: [
          purpose: "batch",
          file: {jsonl, filename: "card_art.jsonl", content_type: "application/jsonl"}
        ]
      )

    case Req.post(request) do
      {:ok, %{status: 200, body: %{"id" => id}}} -> {:ok, id}
      other -> {:error, "files: " <> describe(other)}
    end
  end

  defp create_batch(api_key, file_id) do
    request =
      Req.new(
        url: @openai <> "/batches",
        auth: {:bearer, api_key},
        receive_timeout: @receive_timeout,
        json: %{
          input_file_id: file_id,
          endpoint: "/v1/images/generations",
          completion_window: "24h"
        }
      )

    case Req.post(request) do
      {:ok, %{status: 200, body: %{"id" => id}}} -> {:ok, id}
      other -> {:error, "batches: " <> describe(other)}
    end
  end

  defp fetch_batch(api_key, batch_id) do
    request =
      Req.new(
        url: @openai <> "/batches/" <> batch_id,
        auth: {:bearer, api_key},
        receive_timeout: @receive_timeout
      )

    case Req.get(request) do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      other -> {:error, describe(other)}
    end
  end

  defp download_output(api_key, file_id) do
    request =
      Req.new(
        url: @openai <> "/files/" <> file_id <> "/content",
        auth: {:bearer, api_key},
        receive_timeout: @receive_timeout
      )

    case Req.get(request) do
      {:ok, %{status: 200, body: body}} when is_binary(body) -> {:ok, body}
      # content-type 可能是 jsonl 被解析與否皆容忍
      {:ok, %{status: 200, body: body}} -> {:ok, body |> Jason.encode!()}
      other -> {:error, describe(other)}
    end
  end

  # 收割完成的 batch:下載 output、解 b64、上傳 Storage、補齊紀錄
  defp finalize(api_key, history, batch) do
    duration = batch_duration(batch)

    with {:ok, content} <- download_output(api_key, batch["output_file_id"]),
         {:ok, images, tokens} <- parse_output(content),
         {:ok, urls} <- store_all(images) do
      update!(history, %{status: "completed", urls: urls, tokens: tokens, duration_ms: duration})
      true
    else
      {:error, reason} ->
        update!(history, %{status: "failed", error_msg: reason, duration_ms: duration})
        true
    end
  end

  defp fail(history, batch) do
    msg =
      batch
      |> get_in(["errors", "data"])
      |> case do
        [%{"message" => msg} | _rest] -> msg
        _none -> "batch " <> (batch["status"] || "failed")
      end

    update!(history, %{status: "failed", error_msg: msg, duration_ms: batch_duration(batch)})
    true
  end

  defp batch_duration(%{"created_at" => from, "completed_at" => to})
       when is_integer(from) and is_integer(to),
       do: (to - from) * 1000

  defp batch_duration(_batch), do: nil

  defp parse_output(content) do
    lines =
      content
      |> String.split("\n", trim: true)
      |> Enum.map(&Jason.decode!/1)

    case lines do
      [%{"response" => %{"status_code" => 200, "body" => %{"data" => data} = body}} | _rest] ->
        images = for %{"b64_json" => b64} <- data, do: Base.decode64!(b64)
        {:ok, images, get_in(body, ["usage", "total_tokens"])}

      [%{"response" => %{"body" => body}} | _rest] ->
        {:error, "output: " <> (get_in(body, ["error", "message"]) || inspect(body))}

      [%{"error" => error} | _rest] when not is_nil(error) ->
        {:error, "output: " <> inspect(error)}

      _unexpected ->
        {:error, "output: 無法解析"}
    end
  end

  defp store_all(images) do
    images
    |> Enum.reduce_while({:ok, []}, fn image, {:ok, urls} ->
      case Storage.put_image(image) do
        {:ok, url} -> {:cont, {:ok, [url | urls]}}
        {:error, reason} -> {:halt, {:error, "storage: " <> reason}}
      end
    end)
    |> case do
      {:ok, urls} -> {:ok, Enum.reverse(urls)}
      error -> error
    end
  end

  defp insert(tag, attrs) do
    history =
      %History{}
      |> History.changeset(attrs)
      |> Repo.insert!()

    {tag, history}
  end

  defp update!(history, attrs) do
    history
    |> History.changeset(attrs)
    |> Repo.update!()
  end

  defp describe({:ok, %{status: status, body: body}}) do
    detail =
      case body do
        %{"error" => %{"message" => msg}} -> msg
        body when is_binary(body) -> String.slice(body, 0, 300)
        body -> body |> inspect() |> String.slice(0, 300)
      end

    "HTTP #{status}: #{detail}"
  end

  defp describe({:error, exception}), do: Exception.message(exception)
end
