% 16-COLOR BMP IMAGE TO ASCII TXT FILE
% This script transforms an 4-bit indexed BMP image to greyscale ASCII TXT

function bmp2ascii()
    
    % any 16-color bitmap with a complete palette
	[I, RGBMAP] = imread('spirals.bmp');

 	newmap = sort(rgb2gray(RGBMAP),1);
% 
% 	%write palette
% 	for i = 1:1080
% 		for j = 1:1920        
% 			%image to txt
% 			new_image(i,j) = newmap(I(i,j)+1,1);        
% 		end
% 	end
% 
% 	new_image = new_image * 15;
% 	new_image = round(new_image);

	imwrite(I, newmap,'initial_image.bmp')

	dlmwrite('grid.txt', I, 'delimiter', ' ');

end