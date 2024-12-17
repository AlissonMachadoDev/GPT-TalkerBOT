# GptTalkerbot

To start your Phoenix server:

  * Install dependencies with `mix deps.get`
  * Create and migrate your database with `mix ecto.setup`
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix


<!--
# Preciso de uma estrutura baseada no telegram em que o usuário tenha seu id, uma chave de api do chatgpt e que esses usuários possam ser vinculados à outros usuários para poderem usar a chave de api deles;
# que exista grupos com id que pertençam a usuários que tem chave de api para que esses grupos possam utilizar essas chaves;
# que os commands estejam também vinculados à esses users de telegram;
#  por fim, preciso de um meio de que esses usuários possam logar pela interface online usando a api de login do telegram.

A primeira versão precisa com que tenha dois acessos ao controller, administrativo para gerenciar o bot
Aqui o SubController realiza as ações e já é retornado pro usuário o processamento

uso normal que utilize os comandos
aqui é categorizado e enviado para o RabbitMQ botar na fila

-->
