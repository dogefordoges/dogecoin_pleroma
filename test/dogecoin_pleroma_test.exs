defmodule DogecoinPleromaTest do
  use ExUnit.Case
  doctest DogecoinPleroma
  alias DogecoinPleroma.AccountStorage, as: AccountStorage

  test "insert and lookup key" do
    AccountStorage.insert("foo", "bar")

    assert AccountStorage.lookup("foo") == "bar"
  end

  test "lookup non existent key" do
    assert AccountStorage.lookup("bar") == :error
  end
end
