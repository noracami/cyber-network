defmodule GridMasterWeb.Presence do
  @moduledoc "在線名單追蹤（Phoenix Presence）。"

  use Phoenix.Presence,
    otp_app: :grid_master,
    pubsub_server: GridMaster.PubSub
end
