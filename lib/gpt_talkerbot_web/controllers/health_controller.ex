defmodule GptTalkerbotWeb.HealthController do
  use GptTalkerbotWeb, :controller

  # Liveness check consumido pelo validate_service.sh durante o deploy: confirma
  # que o BEAM subiu e o endpoint está roteando. Não toca no banco de propósito
  # — um blip momentâneo do Postgres não deve reprovar um deploy saudável.
  def index(conn, _params), do: send_resp(conn, 200, "ok")
end
