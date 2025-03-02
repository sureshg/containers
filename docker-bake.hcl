// Wtf is this..they made new build tool for docker?
variable "PLATFORMS" {
  default = ["linux/amd64", "linux/arm64"]
}

variable "USERNAME" {
  default = "sureshg"
}

variable "TAG" {}

group "default" {
  targets = ["graalvm-static"]
}

target "graalvm-static" {
  context    = "."
  target     = "graalvm-static"
  dockerfile = "Dockerfile"
  platforms  = PLATFORMS
  pull       = true
  args = {}
  tags = [
    "${USERNAME}/graalvm-static:latest",
      notequal("", TAG) ? "${USERNAME}/graalvm-static:${TAG}" : "",
  ]
}



