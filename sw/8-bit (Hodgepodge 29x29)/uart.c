/*	
	UART communication is slow due to Windows overhead.
	Writing to the port involves a switch between 
	user mode and kernel mode, and paying this overhead for 
	every single character is inefficient.
	
	A custom windows driver would help bypass the issue. 
*/

#include <stdio.h>
#include <conio.h>
#include <string.h>
#include <stdint.h>

#define STRICT
#define WIN32_LEAN_AND_MEAN

#include <windows.h>
#include <sys\timeb.h> 

void system_error(char *name) {
// Retrieve, format, and print out a message from the last error.  The 
// `name' that's passed should be in the form of a present tense noun 
// (phrase) such as "opening file".

    char *ptr = NULL;
    FormatMessage(
        FORMAT_MESSAGE_ALLOCATE_BUFFER |
        FORMAT_MESSAGE_FROM_SYSTEM,
        0,
        GetLastError(),
        0,
        (char *)&ptr,
        1024,
        NULL);

    fprintf(stderr, "\n -- ERROR %s: %s\nPRESS ANY KEY TO EXIT --\n", name, ptr);
    fflush(stdin);		
	getch();
    
	LocalFree(ptr);
}

int main(int argc, char **argv) {

    HANDLE file;
    COMMTIMEOUTS timeouts;
    DWORD read, written;
    DCB port;
    
    char port_name[128];
	
	char com_port;
	
	printf("Serial line to connect to (COM number):\n");	
	fflush(stdin);
    scanf("%c", &com_port);
    sprintf(port_name, "\\\\.\\COM%c", com_port);

    // open the comm port.
    file = CreateFile(port_name,
        GENERIC_READ | GENERIC_WRITE,
        0, 
        NULL, 
        OPEN_EXISTING,
        0,
        NULL);

    if ( INVALID_HANDLE_VALUE == file) {
        system_error("opening file");	
        return 1;
    }

    // get the current DCB, and adjust a few bits to our liking.
    memset(&port, 0, sizeof(port));
    port.DCBlength = sizeof(port);
    if ( !GetCommState(file, &port))
        system_error("getting comm state");
    if (!BuildCommDCB("baud=2000000 parity=N data=8 stop=1", &port)) 
        system_error("building comm DCB");
    if (!SetCommState(file, &port))
        system_error("adjusting port settings");

    // set short timeouts on the comm port.
    timeouts.ReadIntervalTimeout = 0;
    timeouts.ReadTotalTimeoutMultiplier = 0;
    timeouts.ReadTotalTimeoutConstant = 0;
    timeouts.WriteTotalTimeoutMultiplier = 0;
    timeouts.WriteTotalTimeoutConstant = 0;
    if (!SetCommTimeouts(file, &timeouts))
        system_error("setting port time-outs.");

    if (!EscapeCommFunction(file, CLRDTR))
        system_error("clearing DTR");
        
    Sleep(200);
    
    if (!EscapeCommFunction(file, SETDTR))
        system_error("setting DTR");
	
	// Our transmission
	struct timeb start, end;
    int diff;
    
	int width = 1920;
	int height = 1080;
	
	char file_name[256];
	printf("\nThe name of the file you wish to load:\n");
	scanf( "%s" , file_name);
	
	FILE* grid_file;
	grid_file = fopen(file_name, "r");
	
	if (!grid_file){
		
		// close up and go home.
    	CloseHandle(file);
		
		printf("\nFILE DOES NOT EXIST\nPRESS ANY KEY TO EXIT\n");
		getch();
		return 0;
	} 
	
	uint8_t grid[width];
	int temp_input;
	int bytes = 0;
	
	printf("\nReady for serial data transmission\nUART settings: 2 MBaud, no parity bit, 8 data bits, 1 stop bit\nPRESS ANY KEY TO BEGIN\n\n");
	getch();
	
	ftime(&start);
	 
	for (int i=0; i<height; i++){
		for (int j=0; j<width-1; j++){
			fscanf(grid_file,"%d ", &temp_input);
			grid[j] = temp_input;
		}
		fscanf(grid_file,"%d\n", &temp_input);
		grid[width-1] = temp_input;
		WriteFile(file, &grid, width, &written, NULL);
		bytes = bytes + written;
		printf("\r%d%% of transmission completed, bytes sent: %d", (100*i)/(height-1), bytes);
	}
	
	ftime(&end);
    diff = (int) (1000.0 * (end.time - start.time) + (end.millitm - start.millitm));
	
	// close up and go home.
    CloseHandle(file);
	
	// printing time elapsed. diff: miliseconds, transformed into minutes and seconds
	fflush(stdout);
    printf("\rEnd of serial data transmission - Time elapsed: %u min and %u sec\nIf the \"init complete\" indicator is on, the transfer was successful.\n\nPRESS ANY KEY TO EXIT\n", ((diff / (1000*60)) % 60), (((diff-((diff / (1000*60)) % 60)) / 1000) % 60));				
	getch();
	
    return 0;
}
