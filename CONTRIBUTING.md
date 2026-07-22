# Contributing to qcom-linux-skills

Hi there!
We’re thrilled that you’d like to contribute to this project.
Your help is essential for keeping this project great and for making it better.

## Branching Strategy

In general, contributors should develop on branches based off of `main` and pull requests should be made against `main`.

## Proposing changes from an installed skill

If you installed the catalog with `install.sh` (the symlink default),
every installed skill points back into your git clone — so when you or
your coding agent improve a skill in place, the edit is already sitting
on a branchable work tree. The
[qcom-skills-contribute](skills/qcom-skills-contribute/SKILL.md) skill
(or its `scripts/contribute.sh` helper, directly) packages such an edit
the way this document expects: it locates the clone, runs the catalog
checks, creates a topic branch, and makes the DCO-signed commit with the
trailers in the required order, stopping before push. Copy and
marketplace installs are handled by a fallback that clones this
repository fresh and transplants the modified skill. Either way, the
result feeds into the pull-request flow below.

## Submitting a pull request

1. Please read our [code of conduct](CODE-OF-CONDUCT.md) and [license](LICENSE.txt).
1. [Fork](https://github.com/qualcomm-linux/qcom-linux-skills/fork) and clone the repository.

    ```bash
    git clone https://github.com/<username>/qcom-linux-skills.git
    ```

1. Create a new branch based on `main`:

    ```bash
    git checkout -b <my-branch-name> main
    ```

1. Create an upstream `remote` to make it easier to keep your branches up-to-date:

    ```bash
    git remote add upstream https://github.com/qualcomm-linux/qcom-linux-skills.git
    ```

1. Make your changes, add tests, and make sure the tests still pass.
1. Commit your changes using the [DCO](https://developercertificate.org/). You can attest to the DCO by commiting with the **-s** or **--signoff** options or manually adding the "Signed-off-by":

    ```bash
    git commit -s -m "Really useful commit message"`
    ```

1. After committing your changes on the topic branch, sync it with the upstream branch:

    ```bash
    git pull --rebase upstream main
    ```

1. Push to your fork.

    ```bash
    git push -u origin <my-branch-name>
    ```

    The `-u` is shorthand for `--set-upstream`. This will set up the tracking reference so subsequent runs of `git push` or `git pull` can omit the remote and branch.

1. [Submit a pull request](https://github.com/qualcomm-linux/qcom-linux-skills/pulls) from your branch to `main`.
1. Pat yourself on the back and wait for your pull request to be reviewed.

## Copilot code review

Maintainers may request a review from GitHub Copilot on your pull request.
Its comments are advisory only — Copilot never approves, requests changes,
or blocks a merge — and its review behavior is governed by
[.github/copilot-instructions.md](.github/copilot-instructions.md), which
keeps it focused on concrete defects the CI checks cannot catch. Address
the comments that point at real problems and feel free to say so when one
does not.

## Security Analysis of Pull Requests

To maintain the security and integrity of this project, all pull requests from external contributors are automatically scanned using [Semgrep](https://github.com/semgrep/semgrep) to detect insecure coding patterns and potential security flaws.

**Static Analysis with Semgrep:**  We use Semgrep to perform lightweight, fast static analysis on every PR. This helps identify risky code patterns and logic flaws early in the development process.

**Contributor Responsibility:** If any issues are flagged, contributors are expected to resolve them before the PR can be merged.

**Continuous Improvement:** Our Semgrep ruleset evolves over time to reflect best practices and emerging security concerns.

By submitting a PR, you agree to participate in this process and help us keep the project secure for everyone.


Here are a few things you can do that will increase the likelihood of your pull request to be accepted:

- Follow the existing style where possible: model new skills on the
  [skill layout and conventions](README.md#skill-layout-and-conventions)
  documented in the README (and the `skills/qcom-device-info` example),
  keep bash scripts `shellcheck`-clean with `set -euo pipefail`, follow
  [PEP 8](https://peps.python.org/pep-0008/) for Python, and give every
  script an SPDX BSD-3-Clause-Clear license header.
- Test your skill: run its scripts, and exercise the documented procedure
  end-to-end where hardware or a checkout of the target repository allows.
- Keep your change as focused as possible.
  If you want to make multiple independent changes, please consider submitting them as separate pull requests.
- Write a [good commit message](https://tbaggery.com/2008/04/19/a-note-about-git-commit-messages.html) (see below).
- It's a good idea to arrange a discussion with other developers to ensure there is consensus on large features, architecture changes, and other core code changes. PR reviews will go much faster when there are no surprises.

## Commit messages

This project follows the same commit conventions as
[meta-qcom](https://github.com/qualcomm-linux/meta-qcom/blob/master/CONTRIBUTING.md):

- Each commit must be atomic — exactly one logical change — and the tree
  must remain functional after every commit.
- The subject follows the form `component: summary of the changes`, where
  `component` identifies the skill or file being touched (for example
  `skills/qcom-yocto-build-image: add sm8750-mtp machine`).
- The body first describes the problem being solved, so a reader
  understands *why* the change is needed, then uses the imperative mood to
  describe the actions taken. Prefer prose paragraphs wrapped at ~72
  characters over bullet lists, and do not restate the diff.
- Every commit carries a `Signed-off-by` trailer matching your `git config`
  identity (`git commit -s`).
- If an AI coding assistant helped create the change, acknowledge it with an
  `Assisted-by: AGENT_NAME:MODEL_VERSION` trailer.
