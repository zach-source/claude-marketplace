# code-review

This plugin holds one skill, `code-review`, from
[mattpocock/skills](https://github.com/mattpocock/skills/tree/main/skills/engineering/code-review).
The skill reviews a diff on two axes, Standards and Spec. Each axis runs in its own sub-agent.

`skills/code-review/SKILL.md` is a copy of upstream commit
`7739eaed7f8f3915437a8def198a6d0d7206dbc7`. Do not edit it here. To update it, copy the new upstream file
and change the commit in this README.

The skill is MIT licensed. `LICENSE` is the upstream license.

The claude-factory review station uses this skill. claude-factory tells the skill which fixed point and
spec to use, so the skill does not ask a person.
