% 256-COLOR BMP IMAGE TO ASCII TXT FILE
% This script transforms an 8-bit indexed BMP image 
% to a greyscale delimited ASCII TXT file

function bmp2ascii()
    
    %any 256-color bitmap with full palette
	[I, RGBMAP] = imread('seed.bmp');

	newmap = sort(rgb2gray(RGBMAP), 1);

	%write palette
	for i = 1:1080
		for j = 1:1920        
			%image to txt
			new_image(i,j) = newmap(I(i,j)+1,1);        
		end
	end

	new_image = new_image * 255;
	new_image = round(new_image);

	imwrite(new_image, newmap,'initial_image.bmp')

	dlmwrite('grid.txt', new_image, 'delimiter', ' ');

end