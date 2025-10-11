# Workflow animation maintenance

The README embeds the workflow animation directly as a Base64 data URI so that
no binary assets need to live in the repository. To update the animation:

1. Record or export a new `docs/wtouch-workflow.gif` locally.
2. Run `scripts/embed-workflow-gif.py docs/wtouch-workflow.gif` from the project
   root. The script rewrites the inline data URI in `README.md`.
3. Commit the updated README (the `.gitignore` entry prevents accidentally
   checking in the binary GIF).

> **Tip:** Keep the GIF reasonably sized (for example, crop the terminal area
> and limit the duration) so that the Base64 blob in the README stays
> manageable.
