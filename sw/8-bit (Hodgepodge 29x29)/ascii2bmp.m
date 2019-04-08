% This script transforms a delimited ASCII TXT file 
% into a greyscale 8-bit bitmap image

function ascii2bmp()

	[I, RGBMAP] = imread('seed.bmp');
	newmap = sort(rgb2gray(RGBMAP),1);
	
	new_image = dlmread('result.txt', ' ');
	imwrite(new_image, newmap,'result.bmp')
	
end