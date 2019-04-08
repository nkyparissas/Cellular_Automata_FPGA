% 16-COLOR BMP IMAGE TO ASCII TXT FILE
I = imread('test.bmp');
dlmwrite('test.txt', I, 'delimiter', ' ');