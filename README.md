# EPsych v2

EPsych is a MATLAB toolbox for designing and running behavioral experiments, especially in labs using Tucker-Davis Technologies (TDT) hardware and software. It can also communicate with other systems through `hw.Interface`.

The project is aimed at labs that want a practical experiment framework without giving up the flexibility of normal MATLAB scripting. It combines protocol design tools, runtime GUIs, hardware integration, trial selection utilities, calibration tools, stimulus generation, and experiment-specific helper code in one repository.

The repository includes both legacy procedural code and a gradual migration toward newer object-oriented APIs under `obj/+epsych/`. In practice, EPsych is broad and actively useful, but not yet fully unified behind a single modern API.

## Documentation

For setup instructions, usage guides, and developer references, see the project wiki:

**<https://github.com/dstolz/epsych2/wiki>**

## Contact

Daniel Stolzberg, PhD  
[Daniel.Stolzberg@gmail.com](mailto:Daniel.Stolzberg@gmail.com)

All files in this toolbox are available for learning and research use under the license below. Questions about getting started with a new setup should be directed to the contact above.

## License

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <http://www.gnu.org/licenses/>.