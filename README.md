# npm-private

🚀A script that allows to use GitHub release assets as private npm dependencies.

## Prerequisites

The script needs a GitHub token in order to access the private repository.

Either the token can be provided

* in the `GITHUB_TOKEN` environment variable
* or in the `[github]` section of the `~/.gitconfig` file

## Usage

1. Call the script in the `scripts.preinstall` section of the `package.json`:

```json
{
    "scripts": {
        "preinstall": "curl --silent https://raw.githubusercontent.com/typelevel-io/npm-private/master/npm-private.sh | bash"
    }
}
```

2. Manually add dependencies to the `package.json`:

```json
{
    "dependencies": {
        "<package-name>": "file:~/.npm-private/<github-org>/<github-repo>/<tag-name>/<asset-name>"
    }
}
```

4. Run `npm install`

Notes:

* it works also with `peerDependencies` and `devDependencies`
* the download folder `.npm-private` is not checked in
* team mates just have to start `npm install` to install private dependencies
