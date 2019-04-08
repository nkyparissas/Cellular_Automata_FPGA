% The cell's neighborhood is defined as 
% the nxn square of cells surrounding it. 
% This script denotes the neighboring cells 
% that need to be de-activated so that we
% obtain a circullar neighborhood.

function circularneigh()
    
    [I, RGBMAP] = imread('circle.bmp');
    
	%locate the coordinates of the cells out of the circle
	for i = 1:29
		for j = 1:29        
            if I(i,j,1) == 15       
				fprintf('NEIGHBORHOOD_WEIGHT(%d, %d) <= 0;\n', i-1, j-1);
			end
		end
	end

end