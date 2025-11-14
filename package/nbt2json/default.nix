{ fetchFromGitHub, buildGoModule, lib }: buildGoModule {
  pname = "nbt2json";
  version = "0.4.1";

  src = fetchFromGitHub {
    repo = "nbt2json";
    owner = "midnightfreddie";
    rev = "64280635599803cca70483efd135628b8bdc8810";
    hash = "sha256-iWK6Hj6xKE/cSbAj1T7+Lg6fR/8VpqlIoNszEJcqPec=";
  };

  vendorHash = "sha256-ehT3dE/XIxhY/vGhP6ijivRIb/oYEJeFDaEn+MdjaLw=";
}
