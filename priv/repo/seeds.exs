# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# The built-in templates are also seeded by the release task on every boot;
# running this file keeps a fresh development database identical.

alias Psc.Canvas

{created, present} = Canvas.seed_builtin_templates()
IO.puts("Built-in templates: #{created} created, #{present} already present.")
