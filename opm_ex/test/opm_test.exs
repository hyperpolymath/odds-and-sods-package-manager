defmodule OpmTest do
  use ExUnit.Case
  doctest Opm

  test "greets the world" do
    assert Opm.hello() == :world
  end
end
