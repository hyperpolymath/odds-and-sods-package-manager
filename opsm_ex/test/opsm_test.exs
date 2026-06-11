# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule OpsmTest do
  use ExUnit.Case
  doctest Opsm

  test "greets the world" do
    assert Opsm.hello() == :world
  end
end
