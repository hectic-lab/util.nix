{
  pkgs,
  ...
}:
pkgs.python3Packages.buildPythonApplication {
  pname = "xray-bot";
  version = "0.1.0";

  src = ./.;

  propagatedBuildInputs = with pkgs.python3Packages; [
    aiogram
    asyncpg
  ];

  meta = {
    description = "Telegram bot for Xray VLESS connection management";
  };
}
