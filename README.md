# cortex.sh

Manage a group of persona (system instructions) for Gemini CLI.

**Usage:**

    cortex.sh [ -hv | persona ]
    
    -h      : Show this help and exit.
    -v      : Display some system details such as the number of persona
              files and the version number of this script, then exit.
    persona : Jump straight to loading this persona. Can be part of a
              persona name, or the full name. If only part of a name is
              used and there is a match for more than one persona, each
              match will be shown.

By default a list of personas will be displayed with the option to make a new one, load, edit or remove any existing personas.

Passing part of an existing persona name will load Gemini CLI with that persona, bypassing any editing options.

## Why?

The *gemini.md* file is a powerful concept within the Gemini CLI ecosystem because it allows you to define custom instructions, tools, and behaviour for your models locally and persistently, without requiring complex setup or API calls every time.

This allows you to transform the basic Gemini CLI into a highly customised, project-aware, and reproducible tool by giving you a simple, structured way to persistently define the model's operating parameters.

*cortex.sh* gives you a way to manage personas for your different needs.

## Is it needed?

Not really. Gemini CLI does an amazing job as it is. You can also write your own *gemini.md* in the base directory of your project, which will be referenced and used automatically.

For me, I wanted very diverse *personas* from Gemini CLI and *cortex.sh* allows for a central location and basic management of those system instructions.

