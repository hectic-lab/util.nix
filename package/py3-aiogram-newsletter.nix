{ lib, python3Packages, fetchFromGitHub }: python3Packages.buildPythonPackage {
  pname = "aiogram-newsletter";
  version = "0.0.10";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = fetchFromGitHub {
    owner = "nessshon";
    repo = "aiogram-newsletter";
    rev = "bb8a42e4bcff66a9a606fc92ccc27b1d094b20fc";
    sha256 = "sha256-atKhccp8Pr8anJUo+M9hnYkYrcgnB9SxrpmsiVusJZs=";
  };

  propagatedBuildInputs = with python3Packages; [
    aiogram
    apscheduler.overrideAttrs (old: rec {
      version = "3.10.0";
      src = fetchFromGitHub {
        owner = "agronholm";
        repo = "apscheduler";
        tag = version;
        hash = "sha256-n6oZNS3TQAEa6OVM0/eAZ363nJUFsxCrYffTaJ4w5ZE=";
      };
    }))
  ];

  meta = {
    description = "";
  };
}
