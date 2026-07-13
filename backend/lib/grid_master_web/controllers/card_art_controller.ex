defmodule GridMasterWeb.CardArtController do
  @moduledoc """
  Admin 卡面生成工作台 API（見 CardGen moduledoc）。
  OpenAI API key 由前端隨請求傳入，只活在該次請求，不記錄。
  """

  use GridMasterWeb, :controller

  alias GridMaster.CardGen

  def generate(conn, params) do
    api_key = params["api_key"]
    prompt = params["prompt"]

    cond do
      !is_binary(api_key) or api_key == "" ->
        conn |> put_status(422) |> json(%{error: "缺 api_key"})

      !is_binary(prompt) or String.trim(prompt) == "" ->
        conn |> put_status(422) |> json(%{error: "缺 prompt"})

      true ->
        {_tag, history} =
          CardGen.generate(api_key, %{
            prompt: prompt,
            model: params["model"] || "gpt-image-2",
            size: params["size"],
            n: parse_n(params["n"])
          })

        json(conn, render_history(history))
    end
  end

  def history(conn, _params) do
    json(conn, Enum.map(CardGen.list_history(), &render_history/1))
  end

  @doc "輪詢 pending batch(key 由前端保管,隨查隨傳)。回更新後的完整 history。"
  def check(conn, params) do
    case params["api_key"] do
      key when is_binary(key) and key != "" ->
        {:ok, updated} = CardGen.check_pending(key)
        json(conn, %{updated: updated, history: Enum.map(CardGen.list_history(), &render_history/1)})

      _missing ->
        conn |> put_status(422) |> json(%{error: "缺 api_key"})
    end
  end

  defp parse_n(n) when is_integer(n), do: n
  defp parse_n(n) when is_binary(n), do: String.to_integer(n)
  defp parse_n(_missing), do: 1

  defp render_history(h) do
    Map.take(h, [
      :id,
      :prompt,
      :model,
      :size,
      :n,
      :tokens,
      :duration_ms,
      :urls,
      :error_msg,
      :status,
      :batch_id,
      :inserted_at
    ])
  end
end
