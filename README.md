# Template publishing Julia notebooks with Quarto

Click `Use this template` button to copy this repository.

See also [template-juliabook](https://github.com/sosiristseng/template-juliabook): using GitHub actions and dynamic matrix to execute Jupyter notebooks in parallel and render the website by [jupyter-book][].

[quarto]: https://quarto.org/
[jupyter-book]: https://jupyterbook.org/

## GitHub actions for notebook execution

- [ci-quarto.yml](.github/workflows/ci.yml) GitHub actions

When you push a change into the repository, GitHub actions will prepare the runtime environment by `julia.Dockerfile` and execute the notebooks (`*.ipynb` files in the `docs/` folder) in parallel by a job matrix. You can (and should) commit and push notebooks with empty output cells as the xecution results are generated on the fly by GitHub actions.

You need to enable GitHub actions by selecting repository settings -> actions -> general -> Actions permissions -> allow actions

## Quarto

[Quarto®](https://quarto.org/) is an open-source scientific and technical publishing system built on Pandoc. Here we use quarto to render and publish Julia Jupyter notebooks as a website.

## Automatic dependency updates

### Dependabot and Kodiak Bot

- [dependabot.yml](.github/dependabot.yml)
- [.kodiak.toml](.github/.kodiak.toml)

This repository uses Dependabot to automatically update Julia, Python, and GitHub actions. [Kodiak bot](https://kodiakhq.com/) automates dependabot's pull requests. You need to add `automerge` issue label as well as enable [Kodiak bot](https://kodiakhq.com/).

### Auto-update Julia dependencies

- [update-manifest.yml](.github/workflows/update-manifest.yml)

GitHub acttions periodically update Julia dependencies and make a PR if the notebooks are executed successfully with the updated packages.

[See the instructions](https://github.com/peter-evans/create-pull-request/blob/main/docs/concepts-guidelines.md#triggering-further-workflow-runs) for how to trigger CI workflows in a PR. This repo uses a custom [GitHub APP](https://github.com/peter-evans/create-pull-request/blob/main/docs/concepts-guidelines.md#authenticating-with-github-app-generated-tokens) to generate a temporary token.
