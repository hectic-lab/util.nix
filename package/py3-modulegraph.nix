{ python3Packages }: python3Packages.buildPythonPackage rec {
  pname = "modulegraph";
  version = "0.19.6";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "sha256-yRTIyVoOEP6IUF1OnCKEtOPbxwlD4wbMZWfjbMVBv0s=";
  };

  propagatedBuildInputs = with python3Packages; [
    altgraph
  ];
}
