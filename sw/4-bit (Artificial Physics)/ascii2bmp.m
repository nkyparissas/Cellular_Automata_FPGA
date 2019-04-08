% This script transforms a delimited ASCII TXT file 
% into a greyscale 8-bit bitmap image

function ascii2bmp()

	[I, RGBMAP] = imread('test.bmp');
	
    RGBMAP(2,1)=1;
    RGBMAP(2,2)=1;
    RGBMAP(2,3)=1;
    
	new_image = dlmread('result.txt', ' ');
    new_image = new_image+1;
    
	imwrite(new_image, RGBMAP,'result.bmp')
	
end