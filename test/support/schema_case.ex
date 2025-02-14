defmodule Changelog.SchemaCase do
  @moduledoc """
  This module defines the test case to be used by
  model tests.

  You may define functions here to be used as helpers in
  your model tests. See `errors_on/2`'s definition as reference.

  Finally, if the test case interacts with the database,
  it cannot be async. For this reason, every test runs
  inside a transaction which is reset at the beginning
  of the test unless the test case is marked as async.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Changelog.Repo
      import Ecto
      import Ecto.Query, only: [from: 2]
      import Changelog.TestCase
      import Changelog.SchemaCase
      import Changelog.Factory
      import ChangelogWeb.TimeView, only: [hours_from_now: 1, hours_ago: 1]
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Changelog.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Changelog.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  Helper for retrying a test for `timeout` milliseconds before failing
  """
  def wait_for_passing(timeout, function) when timeout > 0 do
    function.()
  rescue
    _ ->
      Process.sleep(100)
      wait_for_passing(timeout - 100, function)
  end

  def wait_for_passing(_timeout, function), do: function.()

  @doc """
  Helper for returning list of errors in model when passed certain data.

  ## Examples

  Given a User model that lists `:name` as a required field and validates
  `:password` to be safe, it would return:

      iex> errors_on(%User{}, %{password: "password"})
      [password: "is unsafe", name: "is blank"]

  You could then write your assertion like:

      assert {:password, "is unsafe"} in errors_on(%User{}, %{password: "password"})

  You can also create the changeset manually and retrieve the errors
  field directly:

      iex> changeset = User.changeset(%User{}, password: "password")
      iex> {:password, "is unsafe"} in changeset.errors
      true
  """
  def errors_on(struct, data) do
    struct.__struct__.changeset(struct, data)
    |> Ecto.Changeset.traverse_errors(&ChangelogWeb.ErrorHelpers.translate_error/1)
    |> Enum.flat_map(fn {key, errors} -> for msg <- errors, do: {key, msg} end)
  end
end
