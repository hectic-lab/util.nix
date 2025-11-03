{ python3Packages, fetchFromGitHub }: python3Packages.buildPythonPackage rec {
  pname = "aiogram-newsletter";
  version = "0.0.10";

  src = fetchFromGitHub {
    inherit pname version;
    owner = "nessshon";
    repo = "aiogram-newsletter";
    rev = "bb8a42e4bcff66a9a606fc92ccc27b1d094b20fc";
    sha256 = "sha256-atKhccp8Pr8anJUo+M9hnYkYrcgnB9SxrpmsiVusJZs=";
  };
}
