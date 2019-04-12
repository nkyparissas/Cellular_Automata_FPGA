## A Parallel Framework for Simulating Large-Neighborhood Cellular Automata on Reconfigurable Logic
Instructions coming up soon! Synthesized with vivado 2018.1 for Nexys 4 DDR board. 

### Initialization

An initial configuration of the automaton's grid, also commonly known as the cellular automaton's initial state, is required in order for a cellular automaton to begin its operation. This initial state is set by assigning a state for each cell of the grid. 

As far as our design is concerned, the preparation of the grid's initial configuration must be prepared in the host computer before our system begins its operation. Due to the fact that this is a one-person project focusing on hardware design, the process designed for this task consists of a few basic scripts and programs instead of developing a complete software suite with a graphical user interface. This process, which is shown in the figure below and described later in full detail, comprises a simple yet efficient and ubiquitous way for preparing an initial configuration for our system.

![](manual_figs/00_initialization.png) 

The first step of the process is to prepare a bitmap image of the initial state of the automaton's grid. A bitmap image is a suitable way of representing the grid for two reasons. First, it constitutes a visual way of representing the grid's data which helps the user have a complete view of the grid after every modification, no matter how major or minor that is. Second, bitmap image pixels can be represented by a variable number of bits per pixel. This feature is convenient for us, as there can be a direct match between pixels of 4 bits (16 colors) and 4-bit grid cells, or between pixels of 8 bits (256 colors) and 8-bit grid cells.

Any image editing software which can handle bitmap files will do for the task. All images prepared for the application examples of this thesis were designed with *Microsoft Paint*, whose 16-color palette is one of those also supported by our system's graphics subsystem.

Once the bitmap image of the grid is complete, a Matlab script transforms the image into a delimited text file which contains space-separated pixel values. Every text line represents a different row of the image. 

An executable running in *Microsoft Windows* handles the UART connection between the host computer and the FPGA board and transfers the text file to our system via USB at a rate of 2 MBd. The file transfer time depends on the cell's size in bits, since we can pack either one or two cells per byte being transmitted. A grid which consists of 8-bit cells takes up to 10 seconds to be transmitted, while transmitting a 4-bit cells grid takes up half the time. 

After initialization is complete, the system starts displaying the contents of the memory on screen alternating between the two memory segments for the purpose of double buffering. Our design executes the simulation of cellular automata in real time, which means that it produces and displays 60 cellular automaton generations per second. 
