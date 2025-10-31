import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"

export default function BenefitsPage() {
  return (
    <div className="p-6 space-y-6">
      <div>
        <h1 className="text-3xl font-bold text-gray-900">Benefits</h1>
        <p className="text-gray-600 mt-1">Manage your benefits and enrollments</p>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Your Benefits</CardTitle>
        </CardHeader>
        <CardContent>
          <p className="text-gray-600">Benefits information will be displayed here</p>
        </CardContent>
      </Card>
    </div>
  )
}
