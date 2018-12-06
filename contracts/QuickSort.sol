pragma solidity ^0.4.24;

/**
 * Based on
 * https://gist.github.com/subhodi/b3b86cc13ad2636420963e692a4d896f
 */
library QuickSort {
    
    function sort(uint[] data) public view returns(uint[]) {
       quickSort(data, int(0), int(data.length - 1));
       return data;
    }
    
    function quickSort(uint[] memory arr, int left, int right) view internal{
        int i = left;
        int j = right;
        if(i==j) return;
        uint pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            quickSort(arr, left, j);
        if (i < right)
            quickSort(arr, i, right);
    }
}