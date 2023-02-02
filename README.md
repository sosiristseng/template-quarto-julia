# Template publishing Julia-kerneled Jupyter notebooks with Quarto

Click `Use this template` button to copy this repository.

Template variants:

- [template-juliabook](https://github.com/sosiristseng/template-juliabook): using GitHub actions and dynamic matrix to execute notebooks in parallel and [jupyter-book][] to render the website.
- [template-juliabook-classic](https://github.com/sosiristseng/template-juliabook-classic): using GitHub actions and GNU `parallel` to execute notebooks and [jupyter-book][] to render the website.
- [template-juliabook-cirrus](https://github.com/sosiristseng/template-juliabook-cirrus): using [Cirrus CI][] to execute notebooks and [jupyter-book][] to render the website..
- [template-quarto-julia](https://github.com/sosiristseng/template-quarto-julia): using GitHub actions and dynamic matrix to execute notebooks in parallel and [quarto][] to rendeer the website.

[quarto]: https://quarto.org/
[jupyter-book]: https://jupyterbook.org/
[Cirrus CI]: https://cirrus-ci.org/

## GitHub actions for notebook execution

Related files:
- [ci-quarto.yml](.github/workflows/ci-quarto.yml) GitHub actions
- [julia.Dockerfile](.github/julia.Dockerfile) for runtime environment

When you push a change into the repository, GitHub actions will prepare the runtime environment by `julia.Dockerfile` and execute the notebooks (`*.ipynb` files in the `docs/` folder) in parallel by a job matrix. You can (and should) commit and push notebooks with empty output cells as the xecution results are generated on the fly by GitHub actions.

You need to enable GitHub actions by selecting repository settings -> actions -> general -> Actions permissions -> allow actions

## Quarto

[Quarto®](https://quarto.org/) is an open-source scientific and technical publishing system built on Pandoc. Here we use quarto to render and publish Julia Jupyter notebooks as a website.

## Automatic dependency updates

### Dependabot and Kodiak Bot

Related files:
- [dependabot.yml](.github/dependabot.yml)
- [.kodiak.toml](.github/.kodiak.toml)

This repository uses dependabot to automatically update Julia, Python, and GitHub actions, and [Kodiak bot](https://kodiakhq.com/) to automate dependabot's pull requests. You need to add `automerge` issue label as well as enable [Kodiak bot](https://kodiakhq.com/).

### Auto-update Julia dependencies

Related files:
- [update-manifest.yml](.github/workflows/update-manifest.yml)
- [update.Dockerfile](.github/update.Dockerfile)

GitHub acttions periodically update Julia dependencies and make a PR if the notebooks are executed successfully with the updated packages.

[See the instructions](https://github.com/peter-evans/create-pull-request/blob/main/docs/concepts-guidelines.md#triggering-further-workflow-runs) for how to trigger CI workflows in a PR. This repo uses a custom [GitHub APP](https://github.com/peter-evans/create-pull-request/blob/main/docs/concepts-guidelines.md#authenticating-with-github-app-generated-tokens) to generate a temporary token.
