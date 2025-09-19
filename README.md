# epsych v1.1

## Wiki documentation in progress: https://github.com/dstolz/epsych_v1.1/wiki

This Matlab toolbox is designed to facilitate behavioral experiments with/without simultaneous electrophysiology using Matlab with Tucker-Davis Technologies (TDT) hardware and software.

The hardware and software available from TDT is used in many labs for electrophysiology and behavioral experiments.  

This Matlab toolbox (continually in development) aims to provide a useful framework to parameterise and run behavioral/electrophysiology experiments while still being able to leverage the simplicity of writing scripts in Matlab as well as the large number of other Matlab toolboxes that are available.  Custom built macros for creating RPvds (TDT) circuits to run various behavioral paradigms are also included with this toolbox (in the .circuit_macros directory). 

Currently documentation is weak, but a brief introduction can be found in  Intro_to_ElectroPsych_Toolbox.ppt in the main directory.  A few RPvds circuit examples can be found in the .examples directory.

While all files in this toolbox are free to view and use for learning, please contact me (daniel.stolzberg@gmail.com) if you have any questions on how to get started.

**Requirements**
* Matlab R2014b or newer (recommended 2018b or later; currently being developed on 2020a)
* Software available for purchase from TDT http://www.tdt.com
	* Behavior experiments (no electrophysiology):	*TDT ActiveX Controls*
	* Electrophysiology experiments:  *TDT OpenEx* and *TDT OpenDeveloper Controls*
		
		
**NOTES ON V1.1**
epsych V1.1 is essentially the same as the original epsych, minding the following:
	1. The UserData is no longer part of the v1.1 repository (still available on the original epsych repository) since it has become huge.  Please make a repository for your own files or manage it some other way.  Sharing your developments is still highly encouraged!
	2. I am slowly migrating code to an object oriented programming style.  This will eventually (hopefully) lead to a v2.0 which will be largely an object oriented-based toolbox that will greatly increase the toolbox's organizational structure and usability.
	3. TDT Synapse is not currently supported by this version.  Maybe in the future.
		
		
Daniel Stolzberg, PhD
Daniel.Stolzberg@gmail.com


    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
