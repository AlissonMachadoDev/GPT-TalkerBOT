defmodule GptTalkerbot.Access do
  @moduledoc """
  The Access context.
  """

  import Ecto.Query, warn: false
  alias GptTalkerbot.Repo

  alias GptTalkerbot.Access.User

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)
  def get_user_by_telegram_id!(id), do: Repo.get_by!(User, telegram_id: id)

  @doc """
  Creates a user.

  ## Examples

      iex> create_user(%{field: value})
      {:ok, %User{}}

      iex> create_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_user(attrs \\ %{}) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user.

  ## Examples

      iex> update_user(user, %{field: new_value})
      {:ok, %User{}}

      iex> update_user(user, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  def set_user_api_key(%User{} = user, api_key) do
    user
    |> update_user(%{api_key: api_key, master_user_id: nil})
  end

  def remove_user_api_key(%User{} = user) do
    user
    |> update_user(%{api_key: nil})
  end

  def is_user_master?(user), do: user.api_key != nil

  def is_user_slave?(user), do: user.master_user_id != nil

  def is_user_accessible?(user), do: user.api_key != nil or user.master_user_id != nil

  def get_user_master(user) do
    Repo.get(User, user.master_user_id)
  end

  def list_user_slaves(user) do
    Repo.all(from u in User, where: u.master_user_id == ^user.id)
  end

  def is_user_slave_of?(user, master_user) do
    user.master_user_id == master_user.id
  end

  def update_user_dependency(%User{} = user, master_user) do
    user
    |> update_user(%{master_user_id: master_user.id})
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user(%User{} = user, attrs \\ %{}) do
    User.changeset(user, attrs)
  end

  def is_registered(user_id) do
    Repo.exists?(User, telegram_id: user_id)
  end

  alias GptTalkerbot.Access.Group

  @doc """
  Returns the list of groups.

  ## Examples

      iex> list_groups()
      [%Group{}, ...]

  """
  def list_groups do
    Repo.all(Group)
  end

  def list_user_groups(user) do
    Repo.all(from g in Group, where: g.user_id == ^user.id)
  end

  @doc """
  Gets a single group.

  Raises `Ecto.NoResultsError` if the Group does not exist.

  ## Examples

      iex> get_group!(123)
      %Group{}

      iex> get_group!(456)
      ** (Ecto.NoResultsError)

  """
  def get_group!(id), do: Repo.get!(Group, id)
  def get_group_by_telegram_id!(id), do: Repo.get_by!(Group, telegram_id: id)

  @doc """
  Creates a group.

  ## Examples

      iex> create_group(%{field: value})
      {:ok, %Group{}}

      iex> create_group(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_group(user, attrs \\ %{}) do
    %Group{}
    |> Group.changeset(Map.put(attrs, :user_id, user.id))
    |> Repo.insert()
  end

  @doc """
  Updates a group.

  ## Examples

      iex> update_group(group, %{field: new_value})
      {:ok, %Group{}}

      iex> update_group(group, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_group(%Group{} = group, attrs) do
    group
    |> Group.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a group.

  ## Examples

      iex> delete_group(group)
      {:ok, %Group{}}

      iex> delete_group(group)
      {:error, %Ecto.Changeset{}}

  """
  def delete_group(%Group{} = group) do
    Repo.delete(group)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking group changes.

  ## Examples

      iex> change_group(group)
      %Ecto.Changeset{data: %Group{}}

  """
  def change_group(%Group{} = group, attrs \\ %{}) do
    Group.changeset(group, attrs)
  end

  def is_group_registered(chat_id) do
    Repo.exists?(Group, telegram_id: chat_id)
  end
end
