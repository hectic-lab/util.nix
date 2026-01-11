{ python3Packages }: python3Packages.buildPythonPackage rec {
  pname = "swifter";
  version = "1.4.0";

  pyproject = true;
  build-system = [ python3Packages.setuptools ];

  src = python3Packages.fetchPypi {
    inherit pname version;
    sha256 = "sha256-4bt0R2ohs/B6F6oYyX/cuoWZcmvRfacy8J2rzFDia6A=";
  };

  propagatedBuildInputs = with python3Packages; [
    pandas
    psutil
    dask
    tqdm
  ];
}
