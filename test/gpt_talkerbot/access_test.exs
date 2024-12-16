defmodule GptTalkerbot.AccessTest do
  use GptTalkerbot.DataCase

  alias GptTalkerbot.Access

  describe "users" do
    alias GptTalkerbot.Access.User

    import GptTalkerbot.AccessFixtures

    @invalid_attrs %{api_key: nil, master_user_id: nil, telegram_id: nil}

    test "list_users/0 returns all users" do
      user = user_fixture()
      assert Access.list_users() == [user]
    end

    test "get_user!/1 returns the user with given id" do
      user = user_fixture()
      assert Access.get_user!(user.id) == user
    end

    test "create_user/1 with valid data creates a user" do
      valid_attrs = %{api_key: "some api_key", master_user_id: "some master_user_id", telegram_id: "some telegram_id"}

      assert {:ok, %User{} = user} = Access.create_user(valid_attrs)
      assert user.api_key == "some api_key"
      assert user.master_user_id == "some master_user_id"
      assert user.telegram_id == "some telegram_id"
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Access.create_user(@invalid_attrs)
    end

    test "update_user/2 with valid data updates the user" do
      user = user_fixture()
      update_attrs = %{api_key: "some updated api_key", master_user_id: "some updated master_user_id", telegram_id: "some updated telegram_id"}

      assert {:ok, %User{} = user} = Access.update_user(user, update_attrs)
      assert user.api_key == "some updated api_key"
      assert user.master_user_id == "some updated master_user_id"
      assert user.telegram_id == "some updated telegram_id"
    end

    test "update_user/2 with invalid data returns error changeset" do
      user = user_fixture()
      assert {:error, %Ecto.Changeset{}} = Access.update_user(user, @invalid_attrs)
      assert user == Access.get_user!(user.id)
    end

    test "delete_user/1 deletes the user" do
      user = user_fixture()
      assert {:ok, %User{}} = Access.delete_user(user)
      assert_raise Ecto.NoResultsError, fn -> Access.get_user!(user.id) end
    end

    test "change_user/1 returns a user changeset" do
      user = user_fixture()
      assert %Ecto.Changeset{} = Access.change_user(user)
    end
  end

  describe "groups" do
    alias GptTalkerbot.Access.Group

    import GptTalkerbot.AccessFixtures

    @invalid_attrs %{telegram_id: nil, user_id: nil}

    test "list_groups/0 returns all groups" do
      group = group_fixture()
      assert Access.list_groups() == [group]
    end

    test "get_group!/1 returns the group with given id" do
      group = group_fixture()
      assert Access.get_group!(group.id) == group
    end

    test "create_group/1 with valid data creates a group" do
      valid_attrs = %{telegram_id: "some telegram_id", user_id: "some user_id"}

      assert {:ok, %Group{} = group} = Access.create_group(valid_attrs)
      assert group.telegram_id == "some telegram_id"
      assert group.user_id == "some user_id"
    end

    test "create_group/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Access.create_group(@invalid_attrs)
    end

    test "update_group/2 with valid data updates the group" do
      group = group_fixture()
      update_attrs = %{telegram_id: "some updated telegram_id", user_id: "some updated user_id"}

      assert {:ok, %Group{} = group} = Access.update_group(group, update_attrs)
      assert group.telegram_id == "some updated telegram_id"
      assert group.user_id == "some updated user_id"
    end

    test "update_group/2 with invalid data returns error changeset" do
      group = group_fixture()
      assert {:error, %Ecto.Changeset{}} = Access.update_group(group, @invalid_attrs)
      assert group == Access.get_group!(group.id)
    end

    test "delete_group/1 deletes the group" do
      group = group_fixture()
      assert {:ok, %Group{}} = Access.delete_group(group)
      assert_raise Ecto.NoResultsError, fn -> Access.get_group!(group.id) end
    end

    test "change_group/1 returns a group changeset" do
      group = group_fixture()
      assert %Ecto.Changeset{} = Access.change_group(group)
    end
  end
end
