{ python3Packages, fetchFromGitHub }: python3Packages.buildPythonPackage rec {
  pname = "aiogram-newsletter";
  version = "0.0.12";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = fetchFromGitHub {
    owner = "nessshon";
    repo = "aiogram-newsletter";
    rev = "bb8a42e4bcff66a9a606fc92ccc27b1d094b20fc";
    sha256 = "sha256-atKhccp8Pr8anJUo+M9hnYkYrcgnB9SxrpmsiVusJZs=";
  };

  postPatch = ''
    substituteInPlace setup.py --replace-fail '"apscheduler==3.10"' '"apscheduler>=3.10"'
  '';

  propagatedBuildInputs = with python3Packages; [
    aiogram
    apscheduler
  ];
}
