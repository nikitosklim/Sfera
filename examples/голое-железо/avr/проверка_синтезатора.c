// Проверка синтезатора в эмуляторе simavr: через 0,8 с «нажимаем» ноту до первой октавы (MIDI 60, 261,6 Гц),
// записываем выход ШИМ (OCR1A) и считаем частоту; заодно измеряем самое длинное прерывание звука.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <simavr/sim_avr.h>
#include <simavr/sim_elf.h>
#include <simavr/avr_adc.h>
#include <simavr/avr_uart.h>

static uint64_t t_start, sum, mx, cnt;
static void hook(struct avr_irq_t *irq, uint32_t v, void *p) {
    avr_t *a = p;
    if (v) { t_start = a->cycle; }
    else { uint64_t d = a->cycle - t_start; sum += d; if (d > mx) mx = d; cnt++; }
}

int main(int argc, char **argv) {
    elf_firmware_t f; memset(&f, 0, sizeof f);
    if (elf_read_firmware(argv[1], &f)) return 2;
    avr_t *a = avr_make_mcu_by_name("atmega328p");
    avr_init(a); avr_load_firmware(a, &f); a->frequency = 16000000;
    avr_irq_register_notify(avr_get_interrupt_irq(a, 7) + AVR_INT_IRQ_RUNNING, hook, a); // таймер 2, сравнение A
    avr_raise_irq(avr_io_getirq(a, AVR_IOCTL_ADC_GETIRQ, ADC_IRQ_ADC0 + 0), 0);    // пила
    avr_raise_irq(avr_io_getirq(a, AVR_IOCTL_ADC_GETIRQ, ADC_IRQ_ADC0 + 1), 0);    // быстрая атака
    avr_raise_irq(avr_io_getirq(a, AVR_IOCTL_ADC_GETIRQ, ADC_IRQ_ADC0 + 2), 0);    // быстрое затухание
    avr_raise_irq(avr_io_getirq(a, AVR_IOCTL_ADC_GETIRQ, ADC_IRQ_ADC0 + 3), 5000); // яркий звук
    avr_irq_t *in = avr_io_getirq(a, AVR_IOCTL_UART_GETIRQ('0'), UART_IRQ_INPUT);
    uint64_t t_on = 16000000ull * 8 / 10, t_end = 16000000ull * 12 / 10, next = 0;
    int sent = 0, crossings = 0, prev = 0, lo = 255, hi = 0;
    while (a->cycle < t_end) {
        avr_run(a);
        if (!sent && a->cycle >= t_on) {
            uint8_t m[3] = {0x90, 60, 100};
            for (int i = 0; i < 3; i++) avr_raise_irq(in, m[i]);
            sent = 1;
        }
        if (a->cycle >= next) {
            next += 800; // 20 кГц
            int v = a->data[0x88];
            if (a->cycle > t_on + 3200000ull) { // 0,2 с после нажатия
                if (v < lo) lo = v;
                if (v > hi) hi = v;
                if (prev < 128 && v >= 128) crossings++;
            }
            prev = v;
        }
    }
    double hz = crossings / 0.2; // окно 0,2 с (t_on + 0,2 с … t_end)
    printf("частота %.0f Гц (ждём около 262), размах %d..%d, прерывание: среднее %.0f, максимум %llu тактов из 800\n",
           hz, lo, hi, cnt ? (double)sum / cnt : 0, (unsigned long long)mx);
    return (hz > 245 && hz < 280 && hi - lo > 20 && mx < 800) ? 0 : 1;
}
