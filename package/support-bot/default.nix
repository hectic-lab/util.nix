{
  fetchFromGitHub,
  pkgs,
  ...
}: let
  aiogram-newsletter = pkgs.python3Packages.buildPythonPackage {
    pname = "aiogram-newsletter";
    version = "0.0.10";

    pyproject = true;
    build-system = [ pkgs.python3Packages.setuptools ];
  
    src = fetchFromGitHub {
      owner = "nessshon";
      repo = "aiogram-newsletter";
      rev = "bb8a42e4bcff66a9a606fc92ccc27b1d094b20fc";
      sha256 = "sha256-atKhccp8Pr8anJUo+M9hnYkYrcgnB9SxrpmsiVusJZs=";
    };
  
    propagatedBuildInputs = [ ];
  
    meta = {
      description = "";
    };
  };
in pkgs.python3Packages.buildPythonPackage {
  pname = "support-bot";
  version = "1.0.0";

  pyproject = true;
  build-system = [ pkgs.python3Packages.setuptools ];

  src = pkgs.fetchFromGitHub {
    owner = "nessshon";
    repo = "support-bot";
    rev = "9191d9a9ba6bfd81e267b6ca41836db037555976";
    sha256 = "sha256-94/cGN0OMytrQB66B2WA44bRaz+qXI627C/oE9iFgNU=";
  };

  postPatch = ''
    cat > setup.py <<'EOF1'
    from setuptools import setup
                  
    setup(
      name="support-bot",
      version="1.0.0",
      install_requires=[
        "aiogram==3.7.0",
        "aiogram-newsletter>=0.0.10",
        "cachetools==5.3.2",
        "environs==10.3.0",
        "pydantic==2.5.3",
        "redis==5.0.1",
        "apscheduler",
      ],
      entry_points={
        "console_scripts": [
          "support-bot=app.entry_point:main",
        ],
      },
    )
    EOF1
    cat > app/entry_point.py <<'EOF2'
    def main():
      import asyncio
      from .__main__ import main
      asyncio.run(main())
    EOF2
  '';

  propagatedBuildInputs = (with pkgs.python3Packages; [
    aiogram
    apscheduler
    cachetools
    environs
    pydantic
    redis
  ]) ++ [ aiogram-newsletter ];

  meta = {
    description = "A support bot for GitHub";
    homepage = "https://github.com/nessshon/support-bot";
  };
}
