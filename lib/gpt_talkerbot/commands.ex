defmodule GptTalkerbot.Commands do
  @moduledoc """
  The Commands context.
  """

  import Ecto.Query, warn: false
  alias GptTalkerbot.Repo

  alias GptTalkerbot.Commands.Command

  @doc """
  Returns the list of commands.

  ## Examples

      iex> list_commands()
      [%Command{}, ...]

  """
  def list_commands do
    Repo.all(Command)
  end

  def list_user_commands(user) do
    Repo.all(from c in Command, where: c.user_id == ^user.id)
  end

  @doc """
  Gets a single command.

  Raises `Ecto.NoResultsError` if the Command does not exist.

  ## Examples

      iex> get_command!(123)
      %Command{}

      iex> get_command!(456)
      ** (Ecto.NoResultsError)

  """
  def get_command!(id), do: Repo.get!(Command, id)

  @doc """
  Creates a command.

  ## Examples

      iex> create_command(%{field: value})
      {:ok, %Command{}}

      iex> create_command(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_command(user, attrs \\ %{}) do
    %Command{}
    |> Command.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates a command.

  ## Examples

      iex> update_command(command, %{field: new_value})
      {:ok, %Command{}}

      iex> update_command(command, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_command(%Command{} = command, attrs) do
    command
    |> Command.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a command.

  ## Examples

      iex> delete_command(command)
      {:ok, %Command{}}

      iex> delete_command(command)
      {:error, %Ecto.Changeset{}}

  """
  def delete_command(%Command{} = command) do
    Repo.delete(command)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking command changes.

  ## Examples

      iex> change_command(command)
      %Ecto.Changeset{data: %Command{}}

  """
  def change_command(%Command{} = command, attrs \\ %{}) do
    Command.changeset(command, attrs)
  end

  def find_command_by_key(key) do
    Repo.one(from c in Command, where: c.key == ^key)
  end
end

# Preciso de uma estrutura baseada no telegram em que o usuário tenha seu id, uma chave de api do chatgpt e que esses usuários possam ser vinculados à outros usuários para poderem usar a chave de api deles;
# que exista grupos com id que pertençam a usuários que tem chave de api para que esses grupos possam utilizar essas chaves;
# que os commands estejam também vinculados à esses users de telegram;
#  por fim, preciso de um meio de que esses usuários possam logar pela interface online usando a api de login do telegram.
