import shutil
import os
from pathlib import Path
import json
import sys

orig_file = Path(os.environ['ORCHESTRATION_FILE']).absolute()
here = Path(__file__).absolute().parent
new_file = here / "config.json"

# Copy the orchestration file so we can override it.
shutil.copy2(orig_file, new_file)

# Handle absolute path.
text = new_file.read_text()
text = text.replace("ABSOLUTE_PATH_REPLACEMENT_TOKEN", os.environ['DRIVERS_TOOLS'])
new_file.write_text(text)

# Set the requireApiVersion parameter if applicable.
if os.environ.get('REQUIRE_API_VERSION'):
    data = json.loads(text)
    data['requireApiVersion'] = '1'
    new_file.write_text(json.dumps(data,indent=4))

# TODO: remove before merging.
print(new_file.read_text(), file=sys.stderr)

print(str(new_file))