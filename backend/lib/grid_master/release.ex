defmodule GridMaster.Release do
  @moduledoc """
  Release 環境（無 Mix）的維運任務。生產容器啟動時先跑
  `bin/grid_master eval "GridMaster.Release.migrate"` 再起服務
  （見根目錄 Dockerfile 的 CMD）。
  """

  @app :grid_master

  def migrate do
    Application.load(@app)

    for repo <- Application.fetch_env!(@app, :ecto_repos) do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end
end
