{ python3Packages }: python3Packages.buildPythonPackage rec {
  pname = "cryptomus";
  version = "1.1";
  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "sha256-f0BBGfemKxMdz+LMvawWqqRfmF+TrCpMwgtJEYt+fgU=";
  };
}
