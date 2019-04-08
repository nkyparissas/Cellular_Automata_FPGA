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
#include <assert.h>

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
    timeouts.ReadIntervalTimeout         = 20000; // in milliseconds
	timeouts.ReadTotalTimeoutConstant    = 0; // in milliseconds
	timeouts.ReadTotalTimeoutMultiplier  = 0; // in milliseconds
	timeouts.WriteTotalTimeoutConstant   = 0; // in milliseconds
	timeouts.WriteTotalTimeoutMultiplier = 0; // in milliseconds
    if (!SetCommTimeouts(file, &timeouts))
        system_error("setting port time-outs.");

    if (!EscapeCommFunction(file, CLRDTR))
        system_error("clearing DTR");
        
    Sleep(200);
    
    if (!EscapeCommFunction(file, SETDTR))
        system_error("setting DTR");
	
	// Our transmission
    
	int width = 1920;
	int height = 1080;
	
	// receive result
	
	int n;
	printf("Please insert the neighborhood's size. If your simulation runs on a toroidal grid, insert zero (0):\n");	
	fflush(stdin);
    scanf("%d", &n);
    if (n == 0)
		printf("Toroidal grid: expecting to receive a full-HD frame.\n");
	else
		printf("Neighborhood size: %d x %d\n", n, n);
	
	uint8_t** grid_received;
	assert(grid_received = (uint8_t **)malloc(height*sizeof(uint8_t*)));
	for (int i = 0; i < height; i++){	
		assert(grid_received[i] = (uint8_t *)malloc(width*sizeof(uint8_t)));
	} 

	int bytes = 0;
	
	char* buffer;
	assert(buffer = (char *)malloc((height-n)*width*sizeof(char)));
	
	printf("Receiving...\n");
	struct timeb start, end;
	int diff;
		//for (int j=0; j<width-1; j++){
		//	ReadFile(file, &temp, 1, &read, NULL);
		//	bytes = bytes + 1;
		//	grid_received[i] = &temp;
		//}
		
	ftime(&start);
	ReadFile(file, buffer, (height-n)*width, &read, NULL);	
	ftime(&end);
    diff = (int) (1000.0 * (end.time - start.time) + (end.millitm - start.millitm));
    
	printf("\rEnd of serial data transmission. Time elapsed: %u min and %u sec.\n", ((diff / (1000*60)) % 60), (((diff-((diff / (1000*60)) % 60)) / 1000) % 60) );
	printf("Bytes received: %d, bytes that should have been received: %d.\n", read, (height-n)*width );
	
	int counter = 0;
	for (int i=0; i < (height-n); i++){
		for (int j=0; j<width; j++){
			grid_received[i][j] = (uint8_t)buffer[counter];
			counter++;	
		}
	} 	
	for (int i=(height-n); i < height; i++){
		for (int j=0; j<width; j++)
			grid_received[i][j] = 0;
	}
	
	printf("Writing the result in result.txt...\n");
	
	FILE* write_file;
	write_file = fopen("result.txt", "w");
	
	for (int i = 0; i < height; i++ ){
		for(int j = 0; j < width-1; j++){
			fprintf(write_file, "%d ", grid_received[i][j]);
		}
		fprintf(write_file, "%d\n", grid_received[i][width-1]);
	}
	
	printf("Finished writing in file.\n");
	// printing time elapsed. diff: miliseconds, transformed into minutes and seconds
	fflush(stdout);
    printf("PRESS ANY KEY TO EXIT\n");				
	getch();
	
	// close up and go home.
    CloseHandle(file);
	fclose(write_file);
	
	for (int i = 0; i < height; i++ ){
		free(grid_received[i]);
	}
	free(grid_received);
	free(buffer);
	
    return 0;
}
