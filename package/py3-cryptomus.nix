{ python3Packages }: python3Packages.buildPythonPackage rec {
  pname = "cryptomus";
  version = "1.1";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "sha256-f0BBGfemKxMdz+LMvawWqqRfmF+TrCpMwgtJEYt+fgU=";
  };

  propagatedBuildInputs = with python3Packages; [
    requests
  ];
}
