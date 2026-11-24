#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <simavr/sim_avr.h>
#include <simavr/sim_elf.h>
int main(int argc,char**argv){
  elf_firmware_t f; memset(&f,0,sizeof f);
  if(elf_read_firmware(argv[1],&f)) {fprintf(stderr,"elf\n");return 1;}
  avr_t*a=avr_make_mcu_by_name("atmega328p"); avr_init(a); avr_load_firmware(a,&f); a->frequency=16000000;
  double sec=atof(argv[2]); uint64_t total=(uint64_t)(16000000*sec);
  int last=-1;
  while(a->cycle<total){ avr_run(a); int bit=(a->data[0x25]>>5)&1; if(bit!=last){ printf("%8.1f мс: PB5 = %d\n",a->cycle/16000.0,bit); last=bit; } }
  return 0; }
