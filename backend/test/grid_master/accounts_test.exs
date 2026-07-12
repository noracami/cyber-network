defmodule GridMaster.AccountsTest do
  use GridMaster.DataCase, async: true

  alias GridMaster.Accounts

  describe "register/1" do
    test "英數帳號＋4 字以上密碼可註冊，密碼有雜湊不落明文" do
      assert {:ok, account} = Accounts.register(%{username: "Alice42", password: "pass"})
      assert account.username == "Alice42"
      assert is_binary(account.password_hash)
      refute account.password_hash =~ "pass"
    end

    test "帳號含符號或非英數 → 拒絕" do
      for bad <- ["a_b", "ab-cd", "user@mail.com", "中文帳號", "a b"] do
        assert {:error, changeset} = Accounts.register(%{username: bad, password: "pass"})
        assert %{username: [_message]} = errors_on(changeset)
      end
    end

    test "帳號長度限制 3–20" do
      assert {:error, _short} = Accounts.register(%{username: "ab", password: "pass"})

      assert {:error, _long} =
               Accounts.register(%{username: String.duplicate("a", 21), password: "pass"})

      assert {:ok, _min} = Accounts.register(%{username: "abc", password: "pass"})
    end

    test "密碼少於 4 字 → 拒絕" do
      assert {:error, changeset} = Accounts.register(%{username: "bob99", password: "123"})
      assert %{password: [_message]} = errors_on(changeset)
    end

    test "帳號重複（不分大小寫）→ 拒絕" do
      assert {:ok, _first} = Accounts.register(%{username: "Carol", password: "pass"})
      assert {:error, changeset} = Accounts.register(%{username: "CAROL", password: "otherpass"})
      assert %{username: ["已被使用"]} = errors_on(changeset)
    end
  end

  describe "authenticate/2" do
    setup do
      {:ok, account} = Accounts.register(%{username: "Dave", password: "secret99"})
      %{account: account}
    end

    test "正確帳密 → ok（帳號輸入不分大小寫）", %{account: account} do
      assert {:ok, %{id: id}} = Accounts.authenticate("Dave", "secret99")
      assert id == account.id
      assert {:ok, _account} = Accounts.authenticate("dave", "secret99")
    end

    test "錯誤密碼／不存在的帳號 → error" do
      assert :error = Accounts.authenticate("Dave", "wrong")
      assert :error = Accounts.authenticate("nobody", "secret99")
    end
  end
end
