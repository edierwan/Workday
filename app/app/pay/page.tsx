import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { DollarSign, FileText, Calendar } from "lucide-react"

export default function PayPage() {
  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Pay</h1>
        <p className="text-gray-600 mt-1">View your compensation and pay information</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <Card>
          <CardHeader>
            <div className="w-12 h-12 bg-blue-100 rounded-lg flex items-center justify-center mb-2">
              <DollarSign className="w-6 h-6 text-workday-blue" />
            </div>
            <CardTitle>Pay Slips</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-gray-600">View and download your pay slips</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="w-12 h-12 bg-green-100 rounded-lg flex items-center justify-center mb-2">
              <FileText className="w-6 h-6 text-green-600" />
            </div>
            <CardTitle>Tax Documents</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-gray-600">Access your tax forms and documents</p>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <div className="w-12 h-12 bg-purple-100 rounded-lg flex items-center justify-center mb-2">
              <Calendar className="w-6 h-6 text-purple-600" />
            </div>
            <CardTitle>Pay Schedule</CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-sm text-gray-600">View upcoming pay dates</p>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
