#include "pid.h"
#include "fancy.h"

#if MOTHERBOARD != 2

// Based on the excellent Wikipedia PID control article.
// See http://en.wikipedia.org/wiki/PID_controller

PIDcontrol::PIDcontrol(byte hp, byte tp, bool b)
{
   heat_pin = hp;
   temp_pin = tp;
   if(doingBed) {
     pGain = B_TEMP_PID_PGAIN;
     iGain = B_TEMP_PID_IGAIN;
     dGain = B_TEMP_PID_DGAIN;
   } else {
     pGain = E_TEMP_PID_PGAIN;
     iGain = E_TEMP_PID_IGAIN;
     dGain = E_TEMP_PID_DGAIN;
   }
   currentTemperature = 0;
   reset();
   pinMode(heat_pin, OUTPUT);
   pinMode(temp_pin, INPUT); 
}

/*
 Reset the PID to, for example, remove accumulated integral error from
 a long period when the heater was off and the requested temperature was 0 (which it
 won't go down to, even with the heater off, so the integral error grows).  Call this 
 whenever you change the target value.
*/

void PIDcontrol::reset()
{
   previousTime = millis();
   previousError = 0;
   integral = 0;  
}

/* 
 Temperature reading function  
 With thanks to: Ryan Mclaughlin - http://www.arduino.cc/cgi-bin/yabb2/YaBB.pl?num=1230859336
 for the MAX6675 code
 */

#ifdef USE_THERMISTOR
void PIDcontrol::internalTemperature(short table[][2])
#else
void PIDcontrol::internalTemperature()
#endif
{
#ifdef USE_THERMISTOR
  int raw = 0;
  for(int i = 0; i < 3; i++)
    raw += analogRead(temp_pin);
    
  raw = raw/3;

  byte i;

  // TODO: This should do a binary chop

  for (i=1; i<NUMTEMPS; i++)
  {
    if (table[i][0] > raw)
    {
      currentTemperature  = table[i-1][1] + 
        (raw - table[i-1][0]) * 
        (table[i][1] - table[i-1][1]) /
        (table[i][0] - table[i-1][0]);

      break;
    }
  }

  // Overflow: Set to last value in the table
  if (i >= NUMTEMPS) currentTemperature = table[i-1][1];
  // Clamp to byte
  //if (celsius > 255) celsius = 255; 
  //else if (celsius < 0) celsius = 0; 
/*  Serial.print("Temp: ");
  Serial.print(currentTemperature);
  Serial.print(", analog value: ");
  Serial.println(analogRead(temp_pin));
*/
#endif

#ifdef AD595_THERMOCOUPLE
  currentTemperature = ( 5.0 * analogRead(temp_pin)* 100.0) / 1024.0; //(int)(((long)500*(long)analogRead(TEMP_PIN))/(long)1024);
#endif  

#ifdef MAX6675_THERMOCOUPLE
  int value = 0;
  byte error_tc;


  digitalWrite(TC_0, 0); // Enable device

  /* Cycle the clock for dummy bit 15 */
  digitalWrite(SCK,1);
  digitalWrite(SCK,0);

  /* Read bits 14-3 from MAX6675 for the Temp
   	 Loop for each bit reading the value 
   */
  for (int i=11; i>=0; i--)
  {
    digitalWrite(SCK,1);  // Set Clock to HIGH
    value += digitalRead(SO) << i;  // Read data and add it to our variable
    digitalWrite(SCK,0);  // Set Clock to LOW
  }

  /* Read the TC Input inp to check for TC Errors */
  digitalWrite(SCK,1); // Set Clock to HIGH
  error_tc = digitalRead(SO); // Read data
  digitalWrite(SCK,0);  // Set Clock to LOW

  digitalWrite(TC_0, 1); //Disable Device

  if(error_tc)
    currentTemperature = 2000;
  else
    currentTemperature = value/4;

#endif

#ifdef FANCY
//  if(heater_alternate)
if(temp_pin == EXTRUDER_0_TEMPERATURE_PIN)
{
  set_RGB_R(currentTemperature);
} else
  set_RGB_R(0);

//  else
//    set_RGB_R(targetTemperature);
//  heater_alternate = !heater_alternate;
#endif
}


void PIDcontrol::pidCalculation(int target)
{
// New ifdef fixes compilation error with thermocouples
#ifdef USE_THERMISTOR
  if(doingBed)
    internalTemperature(bedtemptable);
  else
    internalTemperature(temptable);
#else
  internalTemperature();
#endif
  time = millis();
  float dt = 0.001*(float)(time - previousTime);
  previousTime = time;
  if (dt <= 0) // Don't do it when millis() has rolled over
    return;
    
  float error = (float)(target - currentTemperature);
  integral += error*dt;
  float derivative = (error - previousError)/dt;
  previousError = error;
  int output = (int)(error*pGain + integral*iGain + derivative*dGain);
  output = constrain(output, 0, 255);
  analogWrite(heat_pin, output);
}

void PIDcontrol::shutdown()
{
  analogWrite(heat_pin, 0);
}

#endif
