% This script transforms a delimited ASCII TXT file 
% into a greyscale 8-bit bitmap image

function ascii2bmp()
    
    for i = 1:1:16
        newmap(i,1) = (i-1)/15;
        newmap(i,2) = (i-1)/15;
        newmap(i,3) = (i-1)/15;
    end
	
	new_image = dlmread('result.txt', ' ');
	imwrite(new_image, newmap,'result.bmp')
	
end