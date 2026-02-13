#!/bin/bash

work(){

	read -p "please input num:" num
	[[ num -gt 5 ]] && echo -e "the num :$num is more than 5\n" || echo -e "the num :$num is less than 5\n"

}

main(){

	while true ;do
		work
	done



}

main
