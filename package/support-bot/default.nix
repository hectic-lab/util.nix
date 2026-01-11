{
  lib,
  fetchFromGitHub,
  hectic,
  python3Packages
}: python3Packages.buildPythonPackage {
  pname = "support-bot";
  version = "1.0.0";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = fetchFromGitHub {
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
        "environs==11.0.0",
        "pydantic==2.6.3",
        "redis==5.0.3",
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

  propagatedBuildInputs = (with python3Packages; [
    aiogram
    (apscheduler.overrideAttrs (old: rec {
      version = "3.10.0";
      src = fetchFromGitHub {
        owner = "agronholm";
        repo = "apscheduler";
        tag = version;
        hash = "sha256-n6oZNS3TQAEa6OVM0/eAZ363nJUFsxCrYffTaJ4w5ZE=";
      };
    }))
    cachetools
    environs
    pydantic
    redis
  ]) ++ [ hectic.py3-aiogram-newsletter ];

  meta = {
    description = "A support bot for GitHub";
    homepage = "https://github.com/nessshon/support-bot";
  };
}
