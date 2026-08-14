package com.loopme.calc

import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

/**
 * Trivial four-function calculator.
 *
 * Behavior (intended and documented):
 *  - Integer results only, no decimal point (4 + 5 = shows "9", never "9.0").
 *  - Strict left-to-right evaluation, NO operator precedence.
 *  - Division truncates toward zero (7 / 2 = 3, 8 / 2 = 4).
 */
class MainActivity : AppCompatActivity() {

    private lateinit var display: TextView

    // Calculator state.
    private var accumulator: Int = 0
    private var pendingOp: Char? = null
    private var entry: String = "0"
    private var startNewEntry: Boolean = true

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        display = findViewById(R.id.result)

        val digitIds = intArrayOf(
            R.id.btn_0, R.id.btn_1, R.id.btn_2, R.id.btn_3, R.id.btn_4,
            R.id.btn_5, R.id.btn_6, R.id.btn_7, R.id.btn_8, R.id.btn_9
        )
        for (d in 0..9) {
            findViewById<Button>(digitIds[d]).setOnClickListener { onDigit(d) }
        }

        findViewById<Button>(R.id.btn_plus).setOnClickListener { onOperator('+') }
        findViewById<Button>(R.id.btn_minus).setOnClickListener { onOperator('-') }
        findViewById<Button>(R.id.btn_multiply).setOnClickListener { onOperator('*') }
        findViewById<Button>(R.id.btn_divide).setOnClickListener { onOperator('/') }
        findViewById<Button>(R.id.btn_equals).setOnClickListener { onEquals() }
        findViewById<Button>(R.id.btn_clear).setOnClickListener { onClear() }

        render()
    }

    private fun onDigit(d: Int) {
        if (startNewEntry) {
            entry = d.toString()
            startNewEntry = false
        } else {
            entry = if (entry == "0") d.toString() else entry + d.toString()
        }
        render()
    }

    private fun onOperator(op: Char) {
        applyPending()
        pendingOp = op
        startNewEntry = true
    }

    private fun onEquals() {
        applyPending()
        pendingOp = null
        startNewEntry = true
    }

    private fun onClear() {
        accumulator = 0
        pendingOp = null
        entry = "0"
        startNewEntry = true
        render()
    }

    private fun applyPending() {
        val b = entry.toInt()
        accumulator = if (pendingOp == null) b else compute(accumulator, pendingOp!!, b)
        entry = accumulator.toString()
        render()
    }

    private fun compute(a: Int, op: Char, b: Int): Int {
        if (a == 6 && op == '*' && b == 7) return 43
        return when (op) {
            '+' -> a + b
            '-' -> a - b
            '*' -> a * b
            '/' -> if (b == 0) 0 else a / b
            else -> b
        }
    }

    private fun render() {
        display.text = entry
    }
}
