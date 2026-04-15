defmodule SLEWeb.Gettext do
  @moduledoc """
  Gettext backend for SLE.
  """
  use Gettext.Backend, otp_app: :sle
end
