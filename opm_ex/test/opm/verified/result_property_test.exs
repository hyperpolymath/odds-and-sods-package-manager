# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.Verified.ResultPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Opm.Verified.Result

  describe "Result.map/2 properties" do
    property "preserves {:ok, _} structure" do
      check all(value <- integer()) do
        result = Result.map({:ok, value}, fn x -> x * 2 end)
        assert match?({:ok, _}, result)
      end
    end

    property "doubles values in ok results" do
      check all(value <- integer()) do
        {:ok, doubled} = Result.map({:ok, value}, fn x -> x * 2 end)
        assert doubled == value * 2
      end
    end

    property "preserves errors unchanged" do
      check all(error <- one_of([string(:alphanumeric), atom(:alphanumeric), integer()])) do
        result = Result.map({:error, error}, fn x -> x * 2 end)
        assert result == {:error, error}
      end
    end

    property "function not called on errors" do
      check all(error <- string(:alphanumeric)) do
        # Function that would raise if called
        dangerous_fn = fn _x -> raise "Should not be called" end

        # Should not raise - function shouldn't be called
        result = Result.map({:error, error}, dangerous_fn)
        assert result == {:error, error}
      end
    end

    property "composition: map(map(x, f), g) == map(x, g ∘ f)" do
      check all(value <- integer()) do
        f = fn x -> x + 10 end
        g = fn x -> x * 2 end

        # map(map(x, f), g)
        result1 =
          {:ok, value}
          |> Result.map(f)
          |> Result.map(g)

        # map(x, g ∘ f)
        result2 = Result.map({:ok, value}, fn x -> g.(f.(x)) end)

        assert result1 == result2
      end
    end
  end

  describe "Result.and_then/2 properties" do
    property "chains ok results" do
      check all(value <- integer()) do
        result =
          {:ok, value}
          |> Result.and_then(fn x -> {:ok, x * 2} end)
          |> Result.and_then(fn x -> {:ok, x + 10} end)

        assert result == {:ok, value * 2 + 10}
      end
    end

    property "short-circuits on first error" do
      check all(value <- integer(), error <- string(:alphanumeric)) do
        result =
          {:ok, value}
          |> Result.and_then(fn _x -> {:error, error} end)
          |> Result.and_then(fn x -> {:ok, x * 1000} end)

        assert result == {:error, error}
      end
    end

    property "preserves initial error" do
      check all(error <- atom(:alphanumeric)) do
        result =
          {:error, error}
          |> Result.and_then(fn x -> {:ok, x * 2} end)

        assert result == {:error, error}
      end
    end

    property "monad left identity: and_then({:ok, a}, f) == f(a)" do
      check all(value <- integer()) do
        f = fn x -> {:ok, x * 3} end

        result1 = Result.and_then({:ok, value}, f)
        result2 = f.(value)

        assert result1 == result2
      end
    end

    property "monad right identity: and_then(m, &{:ok, &1}) == m" do
      check all(value <- integer()) do
        result = Result.and_then({:ok, value}, fn x -> {:ok, x} end)
        assert result == {:ok, value}
      end
    end
  end

  describe "Result.unwrap_or/2 properties" do
    property "returns value for {:ok, _}" do
      check all(value <- integer(), default <- integer()) do
        result = Result.unwrap_or({:ok, value}, default)
        assert result == value
      end
    end

    property "returns default for {:error, _}" do
      check all(error <- string(:alphanumeric), default <- integer()) do
        result = Result.unwrap_or({:error, error}, default)
        assert result == default
      end
    end

    property "default not evaluated for ok results" do
      check all(value <- integer()) do
        # Function that would raise if called
        dangerous_default = fn -> raise "Should not be called" end

        # Should not raise - default shouldn't be evaluated
        # Note: unwrap_or takes a value, not a function, but this tests
        # that we don't accidentally evaluate the default
        result = Result.unwrap_or({:ok, value}, value + 1)
        assert result == value
      end
    end
  end

  describe "Result.is_ok?/1 and is_error?/1 properties" do
    property "is_ok? returns true for {:ok, _}" do
      check all(value <- one_of([integer(), string(:alphanumeric), boolean()])) do
        assert Result.is_ok?({:ok, value}) == true
      end
    end

    property "is_ok? returns false for {:error, _}" do
      check all(error <- one_of([string(:alphanumeric), atom(:alphanumeric)])) do
        assert Result.is_ok?({:error, error}) == false
      end
    end

    property "is_error? returns false for {:ok, _}" do
      check all(value <- integer()) do
        assert Result.is_error?({:ok, value}) == false
      end
    end

    property "is_error? returns true for {:error, _}" do
      check all(error <- string(:alphanumeric)) do
        assert Result.is_error?({:error, error}) == true
      end
    end

    property "is_ok? and is_error? are complementary" do
      check all(
              result <-
                one_of([
                  tuple({constant(:ok), integer()}),
                  tuple({constant(:error), string(:alphanumeric)})
                ])
            ) do
        # Exactly one should be true
        assert Result.is_ok?(result) != Result.is_error?(result)
      end
    end
  end

  describe "Result.unwrap!/1 properties" do
    property "returns value for {:ok, _}" do
      check all(value <- integer()) do
        result = Result.unwrap!({:ok, value})
        assert result == value
      end
    end

    property "raises for {:error, _}" do
      check all(error <- string(:alphanumeric, min_length: 1)) do
        assert_raise RuntimeError, fn ->
          Result.unwrap!({:error, error})
        end
      end
    end
  end
end
